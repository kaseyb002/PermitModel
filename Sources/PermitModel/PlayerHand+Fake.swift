import Foundation

extension PlayerHand {
    public static func fake(
        player: Player = .fake(),
        cards: [CardID] = [],
        permits: [Permit] = [],
        remainingSegments: Int = 45
    ) -> PlayerHand {
        PlayerHand(
            player: player,
            cards: cards,
            permits: permits,
            remainingSegments: remainingSegments
        )
    }
}
