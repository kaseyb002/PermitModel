import Foundation

public typealias PermitID = Int

public struct Permit: Equatable, Codable, Identifiable, Sendable {
    public let id: PermitID
    public let city1: City
    public let city2: City
    public let points: Int

    public init(
        id: PermitID,
        city1: City,
        city2: City,
        points: Int
    ) {
        self.id = id
        self.city1 = city1
        self.city2 = city2
        self.points = points
    }
}
