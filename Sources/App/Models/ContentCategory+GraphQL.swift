import Vapor
import Fluent
import GraphQL
import Pagination

extension ContentCategory {

    func graphQLType(_ pageInfo: GraphQLOutputType) throws -> GraphQLOutputType {
        let node = try graphQLNodeType()
        let nodes = GraphQLList(node)

        let edge = try graphQLEdgeType(node)
        let edges = GraphQLList(edge)

        let fields = [
            "nodes": GraphQLField(type: nodes, resolve: graphQLNodesResolver()),
            "edges": GraphQLField(type: edges, resolve: graphQLNodesResolver()),
            "pageInfo": GraphQLField(type: pageInfo, resolve: graphQLEdgePageResolver())
        ]
        return try GraphQLObjectType(name: plural.pascalCase(), fields: fields)
    }

    func rootResolver() -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            guard let request = eventLoopGroup as? Request else {
                throw Abort(.serviceUnavailable)
            }
//        let first = min(args["first"].int ?? 20, 20)
//        let cursor = args["cursor"].string
            let page = args["page"].int
            let per = min(args["per"].int ?? 20, 20) /// TODO: non hardcoded upper limit

            return try self.items.query(on: request).filter(
                    \.state == .published
                ).paginate(
                page: page ?? 1,
                per: per,
                ContentItem.defaultPageSorts
                ).map { page in
                    return page
            }
        }
    }

    func graphQLNodeType() throws -> GraphQLOutputType {
        let node = try GraphQLObjectType(name: name.pascalCase(), fields: graphQLSingleItemFieldsType())
        return node
    }

    func graphQLEdgeType(_ nodeType: GraphQLOutputType) throws -> GraphQLOutputType {
        let edge = try GraphQLObjectType(name: name.pascalCase() + "Edge",
                                         fields: try graphQLEdgeFields(nodeType))
        return edge
    }

    func graphQLPaginationArgs() -> GraphQLArgumentConfigMap {
//        let first = GraphQLArgument(
//            type: GraphQLInt,
//            description: "The number of items to return after the referenced “after” cursor",
//            defaultValue: "20" // TODO: not hardcoded
//        )
//        let after = GraphQLArgument(
//            type: GraphQLString,
//            description: "Cursor used along with the “first” argument to reference where in the dataset to get data"
//        )
        let page = GraphQLArgument(
            type: GraphQLInt,
            description: "The page number to return",
            defaultValue: "1"
        )
        let per = GraphQLArgument(
            type: GraphQLInt,
            description: "The number of items to return per page",
            defaultValue: "20" // TODO: not hardcoded
        )
        return [
//            "first": first,
//            "after": after,
            "page": page,
            "per": per
        ]
    }

    func graphQLEdgeFields(_ nodeType: GraphQLOutputType) throws -> [String: GraphQLField] {
        var fields = [String: GraphQLField]()
//        fields["cursor"] = GraphQLField(type: GraphQLString, resolve: graphQLEdgeCursorResolver())
        fields["node"] = GraphQLField(type: nodeType, resolve: graphQLEdgeNodeResolver())

        return fields
    }

    func graphQLSingleItemFieldsType() throws -> [String: GraphQLField] {
        var fields = [String: GraphQLField]()
        for field in self.template {
            var type = field.type.graphQL
            if field.required {
                type = GraphQLNonNull(type.debugDescription)
            }
            fields[field.name.camelCase()] = GraphQLField(type: type, resolve: graphQLSingleItemResolver(field))
        }
        fields["published"] = GraphQLField(type: GraphQLNonNull(GraphQLString),
                                           resolve: graphQLPublishDateResolver())
        
        fields["authors"] = try graphQLAuthorsField()

        return fields
    }
    
    func graphQLAuthorsField() throws -> GraphQLField {
        let author = try GraphQLObjectType(
            name: "Author",
            fields: ["name": GraphQLField(type: GraphQLNonNull(GraphQLString),
                                          resolve: graphQLAuthorNameResolver())]
        )
        let authors = GraphQLList(author)
        let field = GraphQLField(type: authors, resolve: graphQLAuthorsResolver())
        return field
    }

    func graphQLNodesResolver() -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            guard let page = source as? Page<ContentItem> else {
                throw Abort(.serviceUnavailable)
            }
            return eventLoopGroup.next().newSucceededFuture(result: page.data)
        }
    }

    func graphQLEdgeNodeResolver() -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            guard let item = source as? ContentItem else {
                throw Abort(.serviceUnavailable)
            }
            return eventLoopGroup.next().newSucceededFuture(result: item)
        }
    }

//    func graphQLEdgeCursorResolver() -> GraphQLFieldResolve {
//        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
//            guard let item = source as? ContentItem else {
//                throw Abort(.serviceUnavailable)
//            }
//            /// TODO: cursor calculation from item
//        }
//    }

    func graphQLEdgePageResolver() -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            return eventLoopGroup.next().newSucceededFuture(result: source)
        }
    }


    func graphQLSingleItemResolver(_ field: ContentField) -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            guard let item = source as? ContentItem else {
                throw Abort(.serviceUnavailable)
            }

            let contentValue = item.content.first(where: { $0.name == field.name })?.value
            let value = contentValue?.rawValue
            return eventLoopGroup.next().newSucceededFuture(result: value)
        }
    }
    
    func graphQLPublishDateResolver() -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            guard let item = source as? ContentItem else {
                throw Abort(.serviceUnavailable)
            }
            
            guard let date = item.published else {
                throw Abort(.serviceUnavailable)
            }
            
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(abbreviation: "UTC")!
            formatter.dateFormat = PigeonDateFormat
            
            return eventLoopGroup.future(formatter.string(from: date))
        }
    }
    
    func graphQLAuthorsResolver() -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            guard let item = source as? ContentItem else {
                throw Abort(.serviceUnavailable)
            }
            
            return eventLoopGroup.future(item.authors)
        }
    }
    
    func graphQLAuthorNameResolver() -> GraphQLFieldResolve {
        return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
            guard let author = source as? PublicUser else {
                throw Abort(.serviceUnavailable)
            }
            
            return eventLoopGroup.future(author.name)
        }
    }

}
