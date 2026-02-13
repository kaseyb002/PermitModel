import Foundation

public struct GameMap: Equatable, Codable, Sendable {
    public let routes: [Route]
    public let permits: [Permit]

    public init(routes: [Route], permits: [Permit]) {
        self.routes = routes
        self.permits = permits
    }
}
