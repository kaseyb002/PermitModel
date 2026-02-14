import Foundation

public enum CardColor: String, Equatable, Codable, CaseIterable, Sendable {
    case purple
    case blue
    case orange
    case white
    case green
    case yellow
    case black
    case red
    case wild

    public static var regularColors: [CardColor] {
        [.purple, .blue, .orange, .white, .green, .yellow, .black, .red]
    }

    public var isWild: Bool { self == .wild }
}
