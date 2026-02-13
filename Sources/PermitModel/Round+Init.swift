import Foundation

extension Round {
    public init(
        id: String = UUID().uuidString,
        started: Date = .now,
        cookedDeck: [Card]? = nil,
        cookedPermits: [Permit]? = nil,
        gameMap: GameMap = .standard(),
        players: [Player],
        segmentsPerPlayer: Int = Round.initialSegments
    ) throws {
        guard players.count >= 2 else { throw PermitModelError.notEnoughPlayers }
        guard players.count <= 5 else { throw PermitModelError.tooManyPlayers }

        self.id = id
        self.started = started

        // Setup cards
        let allCards: [Card] = cookedDeck ?? Card.standardDeck().shuffled()
        var builtCardsMap: [CardID: Card] = [:]
        for card in allCards {
            builtCardsMap[card.id] = card
        }
        self.cardsMap = builtCardsMap

        // Setup routes
        self.routes = gameMap.routes

        // Setup permit deck
        let allPermits: [Permit] = cookedPermits ?? gameMap.permits.shuffled()

        // Deal cards to players
        var remainingCards: [CardID] = allCards.map(\.id)
        var builtPlayerHands: [PlayerHand] = []
        for player in players {
            var hand: [CardID] = []
            for _ in 0..<Self.initialHandSize {
                if !remainingCards.isEmpty {
                    hand.append(remainingCards.removeFirst())
                }
            }
            builtPlayerHands.append(PlayerHand(
                player: player,
                cards: hand,
                permits: [],
                remainingSegments: segmentsPerPlayer
            ))
        }
        self.playerHands = builtPlayerHands

        // Deal face-up cards
        var builtFaceUp: [CardID] = []
        for _ in 0..<Self.faceUpCount {
            if !remainingCards.isEmpty {
                builtFaceUp.append(remainingCards.removeFirst())
            }
        }
        self.faceUpCards = builtFaceUp
        self.drawPile = remainingCards
        self.discardPile = []

        // Deal initial permits (3 per player)
        var remainingPermits: [Permit] = allPermits
        var pendingPlayers: [String] = []
        for i in 0..<builtPlayerHands.count {
            var dealtPermits: [Permit] = []
            for _ in 0..<Self.initialPermitCount {
                if !remainingPermits.isEmpty {
                    dealtPermits.append(remainingPermits.removeFirst())
                }
            }
            self.playerHands[i].permits = dealtPermits
            pendingPlayers.append(builtPlayerHands[i].player.id)
        }
        self.permitDeck = remainingPermits

        self.finalRoundTriggeredBy = nil
        self.turnsRemainingInFinalRound = nil
        self.log = []
        self.ended = nil

        // Set state to setup phase
        self.state = .setup(pendingPermitSelections: pendingPlayers)

        // Handle face-up fiber replacement
        replaceFaceUpIfNeeded()
    }
}
