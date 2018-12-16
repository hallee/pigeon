import Vapor
import Fluent
import Crypto

/// Manages logging in and registering users.
class UserController: PigeonController {

    override func authBoot(router: Router) throws {
        router.get("/login", use: handleUnauthenticatedUser)
        router.post("/login", use: loginUserHandler)
        router.post(User.self, at: "/register", use: registerUserHandler)
    }

}

private extension UserController {

    /// Handles a request from an unauthenticated user.
    /// If any users exist, this generates the login page. If none have been created yet,
    /// the first-time registration page is generated.
    func handleUnauthenticatedUser(_ request: Request) throws -> Future<View> {
        guard try !request.isAuthenticated(User.self) else {
            throw Abort.redirect(to: "/")
        }
        return User.query(on: request).count().flatMap { count -> Future<View> in
            if count > 0 {
                return try generateLoginPage(for: request)
            } else {
                return try generateFirstTimeRegistrationPage(for: request)
            }
        }
    }

    func loginUserHandler(_ request: Request) throws -> Future<Response> {
        guard try !request.isAuthenticated(User.self) else {
            throw Abort.redirect(to: "/users")
        }
        return try request.content.decode(User.self).flatMap { user in
            return User.authenticate(
                using: BasicAuthorization.init(username: user.email,
                                               password: user.password),
                verifier: try request.make(BCryptDigest.self),
                on: request
            ).map { user in
                guard let user = user else {
                    return request.redirect(to: "/")
                }
                try request.authenticate(user)
                return request.redirect(to: "/")
            }
        }
    }

    func registerUserHandler(_ request: Request, newUser: User) throws -> Future<Response> {
        return User.query(on: request).count().flatMap { count -> Future<Response> in
            if count > 0 { // only check authentication if users exist
                // on the first run (no users saved) we should allow registering freely
                guard try request.isAuthenticated(User.self) else {
                    throw Abort(.forbidden)
                }
            }
            /// the first created account starts as an owner; all others start as users
            let privileges: UserPrivileges = count == 0 ? .owner : .user

            return User.query(on: request)
                       .filter(\.email == newUser.email)
                       .first().flatMap { existingUser in
                guard existingUser == nil else {
                    throw Abort(.badRequest, reason: "A user with this email already exists")
                }
                guard !newUser.email.isEmpty, !newUser.password.isEmpty else {
                    throw Abort(.badRequest, reason: "An email and a password are required")
                }

                let digest = try request.make(BCryptDigest.self)
                let hashedPassword = try digest.hash(newUser.password)
                let persistedUser = User(id: nil, name: newUser.name, privileges: privileges,
                                         email: newUser.email, password: hashedPassword)

                return persistedUser.save(on: request).flatMap { _ in
                    return try self.loginUserHandler(request)
                }
            }
        }
    }

}

extension Request {
    func user() throws -> User {
        return try requireAuthenticated(User.self)
    }

    func privileges() throws -> UserPrivileges {
        return try user().privileges ?? .user
    }

    func allUsers() -> Future<[User]> {
        return User.query(on: self).all()
    }
}
