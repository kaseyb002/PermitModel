import Foundation

extension Round {
    public var isComplete: Bool {
        if case .gameComplete = state { return true }
        return false
    }

    public var currentPlayerID: PlayerID? {
        switch state {
        case .waitingForPlayer(let id, _):
            return id
        case .setup, .gameComplete:
            return nil
        }
    }

    public var currentPlayerIndex: Int? {
        guard let playerID = currentPlayerID else { return nil }
        return playerHands.firstIndex(where: { $0.player.id == playerID })
    }

    public func playerHand(for playerID: PlayerID) -> PlayerHand? {
        playerHands.first(where: { $0.player.id == playerID })
    }

    public func player(byID id: PlayerID) -> Player? {
        playerHands.first(where: { $0.player.id == id })?.player
    }

    public var currentPlayer: Player? {
        guard let id = currentPlayerID else { return nil }
        return player(byID: id)
    }

    public func card(byID id: CardID) -> Card? {
        cardsMap[id]
    }

    public var faceUpCardObjects: [Card] {
        faceUpCards.compactMap { cardsMap[$0] }
    }

    /// True if drawing from the pile would succeed (draw pile or discard pile has cards; discard is reshuffled when draw is empty).
    public var canDrawFromPile: Bool {
        !drawPile.isEmpty || !discardPile.isEmpty
    }

    /// True if the current player can draw at least one card (from pile or from face-up).
    public var canDrawAnyCard: Bool {
        canDrawFromPile || !faceUpCards.isEmpty
    }

    public func claimedRoutes(for playerID: PlayerID) -> [Route] {
        routes.filter { $0.claimedBy == playerID }
    }

    public var isFinalRound: Bool {
        finalRoundTriggeredBy != nil
    }
}

extension Round.State {
    public var isComplete: Bool {
        switch self {
        case .gameComplete:
            return true
        case .setup, .waitingForPlayer:
            return false
        }
    }
}
