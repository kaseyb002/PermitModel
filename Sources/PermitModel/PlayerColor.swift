import Foundation

public enum PlayerColor: String, Equatable, Codable, CaseIterable, Sendable {
    case blue
    case red
    case green
    case yellow
    case black

    public var name: String {
        switch self {
        case .blue: "Blue"
        case .red: "Red"
        case .green: "Green"
        case .yellow: "Yellow"
        case .black: "Black"
        }
    }
}
