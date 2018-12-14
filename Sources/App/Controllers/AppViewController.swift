import Vapor

class AppViewController: RouteCollection {
    
    func boot(router: Router) throws {
        router.get("/", use: rootViewHandler)
        router.get("/types", use: typesViewHandler)
        router.get("/types/create", use: createTypesViewHandler)
        router.get("/users", use: usersViewHandler)
    }

}

private extension AppViewController {

    func rootViewHandler(_ request: Request) throws -> Future<View> {
        let privileges = try request.privileges()
        return try generateIndex(for: request, privileges: privileges)
    }
    
    func usersViewHandler(_ request: Request) throws -> Future<View> {
        let user = try request.user()
        let privileges = try request.privileges()
        
        guard privileges.rawValue > UserPrivileges.administrator.rawValue else {
            throw Abort(.unauthorized)
        }
        
        return request.allUsers().flatMap { users in
            return try generateUsers(for: request, currentUser: user, users: users)
        }
    }

    func typesViewHandler(_ request: Request) throws -> Future<View> {
        let user = try request.user()
        let privileges = try request.privileges()

        guard privileges.rawValue > UserPrivileges.administrator.rawValue else {
            throw Abort(.unauthorized)
        }

        return request.allContentTypes().flatMap { contentTypes in
            if contentTypes.count > 0 {
                return try typesView(for: request, currentUser: user, contentTypes: contentTypes)
            } else {
                throw Abort.redirect(to: "/types/create")
            }
        }
    }

    func createTypesViewHandler(_ request: Request) throws -> Future<View> {
        let user = try request.user()
        let privileges = try request.privileges()

        guard privileges.rawValue > UserPrivileges.administrator.rawValue else {
            throw Abort(.unauthorized)
        }

        return request.allContentTypes().flatMap { contentTypes in
            return try createTypesView(for: request, currentUser: user, contentTypes: contentTypes)
        }
    }

}