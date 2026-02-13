import Foundation

extension Round {
    // MARK: - Select Initial Permits (Setup Phase)

    public mutating func selectInitialPermits(playerID: PlayerID, permitIDs: [PermitID]) throws {
        guard case .setup(var pendingPlayers) = state else {
            throw PermitModelError.notInSetupPhase
        }
        guard pendingPlayers.contains(playerID) else {
            throw PermitModelError.playerNotFound
        }
        guard permitIDs.count >= Self.minInitialPermitsToKeep else {
            throw PermitModelError.mustKeepAtLeastTwoInitialPermits
        }

        guard let handIndex = playerHands.firstIndex(where: { $0.player.id == playerID }) else {
            throw PermitModelError.playerNotFound
        }

        let currentPermits: [Permit] = playerHands[handIndex].permits
        let validIDs: Set<PermitID> = Set(currentPermits.map(\.id))
        guard Set(permitIDs).isSubset(of: validIDs) else {
            throw PermitModelError.invalidPermitSelection
        }

        let keptPermits: [Permit] = currentPermits.filter { permitIDs.contains($0.id) }
        let returnedPermits: [Permit] = currentPermits.filter { !permitIDs.contains($0.id) }

        playerHands[handIndex].permits = keptPermits
        permitDeck.append(contentsOf: returnedPermits)

        pendingPlayers.removeAll { $0 == playerID }

        if pendingPlayers.isEmpty {
            state = .waitingForPlayer(id: playerHands[0].player.id, phase: .choosingAction)
        } else {
            state = .setup(pendingPermitSelections: pendingPlayers)
        }
    }

    // MARK: - Draw Card

    public mutating func drawCard(from source: DrawSource) throws {
        guard !isComplete else { throw PermitModelError.gameIsComplete }

        switch state {
        case .waitingForPlayer(let playerID, .choosingAction):
            let cardID: CardID = try removeCard(from: source)
            addCardToPlayer(playerID: playerID, cardID: cardID)

            let drewFaceUpFiber: Bool
            if case .faceUp = source {
                drewFaceUpFiber = cardsMap[cardID]?.isFiber == true
                refillFaceUpCards()
            } else {
                drewFaceUpFiber = false
            }

            if drewFaceUpFiber {
                logAction(playerID: playerID, decision: .drawCards(cardIds: [cardID]))
                advanceToNextPlayer()
            } else if !canDrawAnotherCard {
                logAction(playerID: playerID, decision: .drawCards(cardIds: [cardID]))
                advanceToNextPlayer()
            } else {
                state = .waitingForPlayer(id: playerID, phase: .drawingSecondCard(firstCardId: cardID))
            }

        case .waitingForPlayer(let playerID, .drawingSecondCard(let firstCardID)):
            if case .faceUp(let index) = source {
                guard index < faceUpCards.count else {
                    throw PermitModelError.invalidFaceUpIndex
                }
                guard cardsMap[faceUpCards[index]]?.isFiber != true else {
                    throw PermitModelError.cannotDrawFiberAsSecondCard
                }
            }

            let cardID: CardID = try removeCard(from: source)
            addCardToPlayer(playerID: playerID, cardID: cardID)

            if case .faceUp = source {
                refillFaceUpCards()
            }

            logAction(playerID: playerID, decision: .drawCards(cardIds: [firstCardID, cardID]))
            advanceToNextPlayer()

        default:
            throw PermitModelError.notWaitingForPlayerToAct
        }
    }

    // MARK: - Claim Route

    public mutating func claimRoute(routeID: RouteID, cardIDs: [CardID]) throws {
        guard !isComplete else { throw PermitModelError.gameIsComplete }
        guard case .waitingForPlayer(let playerID, .choosingAction) = state else {
            throw PermitModelError.notInChoosingActionPhase
        }

        guard let routeIndex = routes.firstIndex(where: { $0.id == routeID }) else {
            throw PermitModelError.routeNotFound
        }

        let route: Route = routes[routeIndex]

        guard route.claimedBy == nil else {
            throw PermitModelError.routeAlreadyClaimed
        }

        // Check double route restrictions
        if let partnerID = route.doubleRoutePartnerID {
            if let partnerRoute = routes.first(where: { $0.id == partnerID }) {
                if partnerRoute.claimedBy == playerID {
                    throw PermitModelError.cannotClaimBothDoubleRoutes
                }
                if playerHands.count <= 3 && partnerRoute.claimedBy != nil {
                    throw PermitModelError.doubleRouteBlockedInSmallGame
                }
            }
        }

        guard cardIDs.count == route.length else {
            throw PermitModelError.insufficientCards
        }

        guard let handIndex = playerHands.firstIndex(where: { $0.player.id == playerID }) else {
            throw PermitModelError.playerNotFound
        }

        // Validate cards are in player's hand
        var handCards: [CardID] = playerHands[handIndex].cards
        for cardID in cardIDs {
            guard let idx = handCards.firstIndex(of: cardID) else {
                throw PermitModelError.cardNotInHand
            }
            handCards.remove(at: idx)
        }

        // Validate card colors match route
        try validateCardsForRoute(cardIDs: cardIDs, route: route)

        // Check segments
        guard playerHands[handIndex].remainingSegments >= route.length else {
            throw PermitModelError.notEnoughSegments
        }

        // Execute: claim the route
        routes[routeIndex].claimedBy = playerID
        playerHands[handIndex].cards = handCards
        playerHands[handIndex].remainingSegments -= route.length
        discardPile.append(contentsOf: cardIDs)

        let points: Int = Route.routeScore(length: route.length)
        playerHands[handIndex].player.score += points

        logAction(playerID: playerID, decision: .claimRoute(routeId: routeID, cardIds: cardIDs, points: points))

        checkFinalRoundTrigger(playerID: playerID)
        advanceToNextPlayer()
    }

    // MARK: - Draw Permits

    public mutating func drawPermits() throws {
        guard !isComplete else { throw PermitModelError.gameIsComplete }
        guard case .waitingForPlayer(let playerID, .choosingAction) = state else {
            throw PermitModelError.notInChoosingActionPhase
        }
        guard !permitDeck.isEmpty else {
            throw PermitModelError.noPermitsAvailable
        }

        var drawn: [Permit] = []
        let count: Int = min(3, permitDeck.count)
        for _ in 0..<count {
            drawn.append(permitDeck.removeFirst())
        }

        state = .waitingForPlayer(id: playerID, phase: .choosingPermits(drawn: drawn))
    }

    // MARK: - Keep Permits

    public mutating func keepPermits(permitIDs: [PermitID]) throws {
        guard !isComplete else { throw PermitModelError.gameIsComplete }
        guard case .waitingForPlayer(let playerID, .choosingPermits(let drawn)) = state else {
            throw PermitModelError.notInChoosingPermitsPhase
        }
        guard !permitIDs.isEmpty else {
            throw PermitModelError.mustKeepAtLeastOnePermit
        }

        let drawnIDs: Set<PermitID> = Set(drawn.map(\.id))
        guard Set(permitIDs).isSubset(of: drawnIDs) else {
            throw PermitModelError.invalidPermitSelection
        }

        guard let handIndex = playerHands.firstIndex(where: { $0.player.id == playerID }) else {
            throw PermitModelError.playerNotFound
        }

        let kept: [Permit] = drawn.filter { permitIDs.contains($0.id) }
        let returned: [Permit] = drawn.filter { !permitIDs.contains($0.id) }

        playerHands[handIndex].permits.append(contentsOf: kept)
        permitDeck.append(contentsOf: returned)

        logAction(playerID: playerID, decision: .drawPermits(keptPermitIds: permitIDs))
        advanceToNextPlayer()
    }

    // MARK: - Private Helpers

    private mutating func removeCard(from source: DrawSource) throws -> CardID {
        switch source {
        case .faceUp(let index):
            guard index < faceUpCards.count else {
                throw PermitModelError.invalidFaceUpIndex
            }
            let cardID: CardID = faceUpCards.remove(at: index)
            return cardID

        case .drawPile:
            reshuffleDeckIfNeeded()
            guard !drawPile.isEmpty else {
                throw PermitModelError.noCardsAvailable
            }
            return drawPile.removeFirst()
        }
    }

    private mutating func addCardToPlayer(playerID: PlayerID, cardID: CardID) {
        guard let handIndex = playerHands.firstIndex(where: { $0.player.id == playerID }) else { return }
        playerHands[handIndex].cards.append(cardID)
    }

    mutating func refillFaceUpCards() {
        while faceUpCards.count < Self.faceUpCount {
            reshuffleDeckIfNeeded()
            guard !drawPile.isEmpty else { break }
            faceUpCards.append(drawPile.removeFirst())
        }
        replaceFaceUpIfNeeded()
    }

    mutating func replaceFaceUpIfNeeded() {
        let fiberCount: Int = faceUpCards.filter { cardsMap[$0]?.isFiber == true }.count
        guard fiberCount >= 3 else { return }
        guard !drawPile.isEmpty else { return }

        discardPile.append(contentsOf: faceUpCards)
        faceUpCards = []
        for _ in 0..<Self.faceUpCount {
            if !drawPile.isEmpty {
                faceUpCards.append(drawPile.removeFirst())
            }
        }
        replaceFaceUpIfNeeded()
    }

    private mutating func reshuffleDeckIfNeeded() {
        if drawPile.isEmpty && !discardPile.isEmpty {
            drawPile = discardPile.shuffled()
            discardPile = []
        }
    }

    private var canDrawAnotherCard: Bool {
        if !drawPile.isEmpty || !discardPile.isEmpty { return true }
        return faceUpCards.contains { cardsMap[$0]?.isFiber != true }
    }

    private func validateCardsForRoute(cardIDs: [CardID], route: Route) throws {
        let cards: [Card] = try cardIDs.map { cardID in
            guard let card = cardsMap[cardID] else {
                throw PermitModelError.cardNotFound
            }
            return card
        }

        let nonFiberCards: [Card] = cards.filter { !$0.isFiber }

        switch route.color {
        case .any:
            let colors: Set<CardColor> = Set(nonFiberCards.map(\.color))
            guard colors.count <= 1 else {
                throw PermitModelError.invalidCardColor
            }
        default:
            let requiredCardColor: CardColor? = routeColorToCardColor(route.color)
            for card in nonFiberCards {
                guard card.color == requiredCardColor else {
                    throw PermitModelError.invalidCardColor
                }
            }
        }
    }

    private func routeColorToCardColor(_ routeColor: Route.Color) -> CardColor? {
        switch routeColor {
        case .purple: .purple
        case .blue: .blue
        case .orange: .orange
        case .white: .white
        case .green: .green
        case .yellow: .yellow
        case .black: .black
        case .red: .red
        case .any: nil
        }
    }

    private mutating func checkFinalRoundTrigger(playerID: PlayerID) {
        guard finalRoundTriggeredBy == nil else { return }
        guard let hand = playerHands.first(where: { $0.player.id == playerID }) else { return }
        if hand.remainingSegments <= Self.finalRoundSegmentThreshold {
            finalRoundTriggeredBy = playerID
            // +1 accounts for the advanceToNextPlayer call at the end of the triggering turn
            turnsRemainingInFinalRound = playerHands.count + 1
        }
    }

    private mutating func advanceToNextPlayer() {
        if turnsRemainingInFinalRound != nil {
            turnsRemainingInFinalRound! -= 1
            if turnsRemainingInFinalRound! <= 0 {
                endGame()
                return
            }
        }

        guard let currentIdx = currentPlayerIndex else { return }
        let nextIdx: Int = (currentIdx + 1) % playerHands.count
        state = .waitingForPlayer(id: playerHands[nextIdx].player.id, phase: .choosingAction)
    }

    private mutating func logAction(playerID: PlayerID, decision: Action.Decision) {
        log.append(Action(playerID: playerID, decision: decision, timestamp: .now))
        if log.count > Self.maxLogActions {
            log.removeFirst(log.count - Self.maxLogActions)
        }
    }

    private mutating func endGame() {
        // Calculate permit bonuses/penalties
        for i in 0..<playerHands.count {
            for permit in playerHands[i].permits {
                if isPermitCompleted(permit: permit, playerID: playerHands[i].player.id) {
                    playerHands[i].player.score += permit.points
                } else {
                    playerHands[i].player.score -= permit.points
                }
            }
        }

        // Calculate longest continuous path bonus
        let longestPathPlayerIDs: [String] = playersWithLongestPath()
        for i in 0..<playerHands.count {
            if longestPathPlayerIDs.contains(playerHands[i].player.id) {
                playerHands[i].player.score += 10
            }
        }

        // Determine winner (tiebreaker: most completed permits)
        let winner: Player = playerHands.max(by: { a, b in
            if a.player.score == b.player.score {
                let aCompleted: Int = a.permits.filter { isPermitCompleted(permit: $0, playerID: a.player.id) }.count
                let bCompleted: Int = b.permits.filter { isPermitCompleted(permit: $0, playerID: b.player.id) }.count
                return aCompleted < bCompleted
            }
            return a.player.score < b.player.score
        })!.player

        ended = .now
        state = .gameComplete(winner: winner)
    }
}
