import Foundation

public typealias CardID = String

public struct Card: Equatable, Codable, Identifiable, Hashable, Sendable {
    public let id: CardID
    public let color: CardColor

    public var isWild: Bool { color.isWild }

    public init(id: CardID, color: CardColor) {
        self.id = id
        self.color = color
    }

    public static func standardDeck() -> [Card] {
        var cards: [Card] = []
        for color in CardColor.regularColors {
            for i in 1...12 {
                cards.append(Card(id: "\(color.rawValue)-\(i)", color: color))
            }
        }
        for i in 1...14 {
            cards.append(Card(id: "wild-\(i)", color: .wild))
        }
        return cards
    }

    public static func fake(
        id: CardID = UUID().uuidString,
        color: CardColor = .blue
    ) -> Card {
        Card(id: id, color: color)
    }
}
