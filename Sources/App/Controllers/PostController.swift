import Vapor
import Fluent

class PostController: PigeonController {

    override func loginGuardedBoot(router: Router) throws {
        router.get(["/content", String.parameter], use: postViewController)
        router.get(["/content", String.parameter, "/create"], use: createPostView)
        router.post(GenericContentItem.self, at: ["/content", String.parameter], use: createPostController)
//        router.get(["/content", String.parameter, String.parameter], use: editPostView)
    }

}

private extension PostController {
    
    func postViewController(_ request: Request) throws -> Future<View> {
        guard let typeName = try request.parameters.next(String.self).removingPercentEncoding else {
            throw Abort(.notFound)
        }

        return try request.contentCategory(typePluralName: typeName).flatMap { category in
            return try category.items.query(on: request).range(..<50).all().flatMap { items in
                return try self.generatePostListView(for: request,
                                                     category: category,
                                                     items: items)
            }

        }
    }

    func createPostView(_ request: Request) throws -> Future<View> {
        guard let typeName = try request.parameters.next(String.self).removingPercentEncoding else {
            throw Abort(.notFound)
        }

        return try request.contentCategory(typePluralName: typeName).flatMap { category in
            return try self.generateCreatePostView(for: request,
                                                   category: category)
        }
    }

    func createPostController(_ request: Request, item: GenericContentItem) throws -> Future<View> {
        // TODO: save the item
        print(item)
        fatalError()
    }

    struct PostListPage: Codable {
        var shared: BasePage
        var category: GenericContentCategory
        var items: [GenericContentItem]
        // TODO: page number / paging
    }
    
    func generatePostListView(for request: Request,
                              category: GenericContentCategory,
                              items: [GenericContentItem]) throws -> Future<View> {
        return try request.base().flatMap { basePage in
            let postsPage = PostListPage(shared: basePage,
                                         category: category,
                                         items: items)
            return try request.view().render("Posts/posts", postsPage)
        }
    }

    struct CreatePostPage: Codable {
        var shared: BasePage
        var category: GenericContentCategory
    }

    func generateCreatePostView(for request: Request,
                                category: GenericContentCategory) throws -> Future<View> {
        return try request.base().flatMap { basePage in
            let createPostPage = CreatePostPage(shared: basePage, category: category)
            return try request.view().render("Posts/create-post", createPostPage)
        }
    }
}

extension Request {
    func contentCategory(typePluralName: String) throws -> Future<GenericContentCategory> {
        return GenericContentCategory.query(on: self)
                                     .filter(\.plural == typePluralName)
                                     .first().map { category in
            guard let category = category else {
                throw Abort(.notFound)
            }
            return category
        }
    }
}