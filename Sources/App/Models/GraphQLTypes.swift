import Vapor
import GraphQL
import Pagination

extension SupportedType {
    var graphQL: GraphQLOutputType {
        switch self {
        case .markdown: return GraphQLMarkdownType
        case .string: return GraphQLString
        case .int: return GraphQLInt
        case .float: return GraphQLFloat
        case .bool: return GraphQLBoolean
        case .date: return GraphQLString
        case .url: return GraphQLString
        case .array(let type):
            return GraphQLList(type.graphQL)
        }
    }

    static var graphQLNamedTypes: [GraphQLNamedType] {
        var types = [GraphQLNamedType]()
        if let markdown = SupportedType.markdown.graphQL as? GraphQLNamedType {
            types.append(markdown)
        }
        return types
    }

}

extension SupportedValue {
    var rawValue: Any {
        switch self {
        case .string(let value): return value as Any
        case .bool(let value): return value as Any
        case .markdown(let value): return value as Any
        default:
            fatalError()
        }
    }
}

public var GraphQLPageInfoType: GraphQLOutputType = {
    let paginationResolver: GraphQLFieldResolve = { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
        guard let page = source as? Page<ContentItem> else {
            throw Abort(.serviceUnavailable)
        }
        guard info.path.count > 2 else {
            throw Abort(.serviceUnavailable)
        }
        switch info.path[2].keyValue {
        case "current":
            return eventLoopGroup.next().newSucceededFuture(result: page.number)
        case "total":
            return eventLoopGroup.next().newSucceededFuture(result: Int(ceil(Float(page.total) / Float(page.size))))
        case "size":
            return eventLoopGroup.next().newSucceededFuture(result: page.size)
        default:
            throw Abort(.serviceUnavailable)
        }
    }
    
    var fields = [String: GraphQLField]()
    fields["current"] = GraphQLField(type: GraphQLInt, resolve: paginationResolver)
    fields["size"] = GraphQLField(type: GraphQLInt, resolve: paginationResolver)
    fields["total"] = GraphQLField(type: GraphQLInt, resolve: paginationResolver)
    
    let pageInfo = try! GraphQLObjectType(name: "PageInfo",
                                          fields: fields)
    return pageInfo
}()

public var GraphQLMarkdownType: GraphQLOutputType = {
    let fields = [
        "html": GraphQLField(
            type: GraphQLString,
            resolve: { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
                guard let markdown = source as? Markdown else {
                    return eventLoopGroup.future(nil)
                }
                return eventLoopGroup.future(markdown.html)
        }),
        "markdown": GraphQLField(
            type: GraphQLString,
            resolve: { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
                guard let markdown = source as? Markdown else {
                    return eventLoopGroup.future(nil)
                }
                return eventLoopGroup.future(markdown.markdown)
            })
    ]
    return try! GraphQLObjectType(name: "Markdown",
                                  fields: fields)
}()

public var GraphQLAuthorType: GraphQLOutputType = {
    let fields = [
        "name": GraphQLField(
            type: GraphQLNonNull(GraphQLString),
            resolve: { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
                return eventLoopGroup.future((source as? PublicUser)?.name)
            })
    ]
    return try! GraphQLObjectType(name: "Author",
                                  fields: fields)
}()

public var GraphQLPostMetaType: GraphQLOutputType = {
    let fields = [
        "authors": GraphQLField(
            type: GraphQLList(GraphQLAuthorType),
            resolve: { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
                return eventLoopGroup.future((source as? ContentItem)?.authors)
            }),
        "published": GraphQLField(
            type: GraphQLNonNull(GraphQLString),
            resolve: { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
                guard let item = source as? ContentItem else {
                    throw Abort(.serviceUnavailable)
                }
                
                guard let date = item.published else {
                    throw Abort(.serviceUnavailable)
                }
                
                let formatter = DateFormatter.iso8601
                return eventLoopGroup.future(formatter.string(from: date))
            })
    ]
    return try! GraphQLObjectType(name: "Meta",
                                  fields: fields)
}()

public var GraphQLPassthroughResolver: GraphQLFieldResolve = {
    return { (source, args, context, eventLoopGroup, info) -> EventLoopFuture<Any?> in
        return eventLoopGroup.future(source)
    }
}()


