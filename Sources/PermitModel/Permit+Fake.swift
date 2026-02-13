import Foundation

extension Permit {
    public static func fake(
        id: PermitID = 0,
        city1: City = .losAngeles,
        city2: City = .newYork,
        points: Int = 21
    ) -> Permit {
        Permit(
            id: id,
            city1: city1,
            city2: city2,
            points: points
        )
    }
}
