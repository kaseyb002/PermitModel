import Foundation

public struct PlayerHand: Equatable, Codable, Sendable {
    public var player: Player
    public var cards: [CardID]
    public var permits: [Permit]
    public var remainingSegments: Int

    public init(
        player: Player,
        cards: [CardID] = [],
        permits: [Permit] = [],
        remainingSegments: Int = 45
    ) {
        self.player = player
        self.cards = cards
        self.permits = permits
        self.remainingSegments = remainingSegments
    }
}
