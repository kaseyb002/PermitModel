import Foundation

extension Route {
    public static func fake(
        id: RouteID = 0,
        city1: City = .losAngeles,
        city2: City = .newYork,
        length: Int = 3,
        color: Color = .any,
        doubleRoutePartnerID: RouteID? = nil,
        claimedBy: PlayerID? = nil
    ) -> Route {
        Route(
            id: id,
            city1: city1,
            city2: city2,
            length: length,
            color: color,
            doubleRoutePartnerID: doubleRoutePartnerID,
            claimedBy: claimedBy
        )
    }
}
