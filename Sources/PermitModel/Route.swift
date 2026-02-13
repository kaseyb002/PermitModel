import Foundation

public typealias RouteID = Int

public struct Route: Equatable, Codable, Identifiable, Sendable {
    public let id: RouteID
    public let city1: City
    public let city2: City
    public let length: Int
    public let color: Color
    public let doubleRoutePartnerID: RouteID?
    public var claimedBy: PlayerID?

    public enum Color: String, Equatable, Codable, Sendable {
        case purple
        case blue
        case orange
        case white
        case green
        case yellow
        case black
        case red
        case any
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case city1
        case city2
        case length
        case color
        case doubleRoutePartnerID = "doubleRoutePartnerId"
        case claimedBy
    }

    public init(
        id: RouteID,
        city1: City,
        city2: City,
        length: Int,
        color: Color,
        doubleRoutePartnerID: RouteID? = nil,
        claimedBy: PlayerID? = nil
    ) {
        self.id = id
        self.city1 = city1
        self.city2 = city2
        self.length = length
        self.color = color
        self.doubleRoutePartnerID = doubleRoutePartnerID
        self.claimedBy = claimedBy
    }

    public static func routeScore(length: Int) -> Int {
        switch length {
        case 1: 1
        case 2: 2
        case 3: 4
        case 4: 7
        case 5: 10
        case 6: 15
        default: 0
        }
    }
}
