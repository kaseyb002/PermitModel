import Foundation

extension Round {
    // MARK: - Select Initial Permits (Setup Phase)

    /// During the setup phase, allows a player to choose which permits to keep from their initial draw.
    /// - Parameters:
    ///   - playerID: The player making the selection.
    ///   - permitIDs: The permit IDs to keep; the rest are returned to the deck. Must keep at least two permits.
    /// - Throws: `PermitModelError` if not in setup phase, player not found, or selection is invalid.
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

        guard let handIndex: Int = playerHands.firstIndex(where: { $0.player.id == playerID }) else {
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

    /// Draws a card from the deck or face-up display for the current player.
    /// Drawing a face-up wild on the first draw ends the turn immediately.
    /// - Parameter source: Where to draw from (e.g., deck or face-up card at index).
    /// - Throws: `PermitModelError` if the game is complete, not waiting for the player to act, or the source is invalid.
    public mutating func drawCard(from source: DrawSource) throws {
        guard isComplete == false else {
            throw PermitModelError.gameIsComplete
        }

        switch state {
        case .waitingForPlayer(let playerID, .choosingAction):
            let cardID: CardID = try removeCard(from: source)
            addCardToPlayer(playerID: playerID, cardID: cardID)

            let drewFaceUpWild: Bool
            if case .faceUp = source {
                drewFaceUpWild = cardsMap[cardID]?.isWild == true
            } else {
                drewFaceUpWild = false
            }
            refillFaceUpCards()

            if drewFaceUpWild {
                logAction(playerID: playerID, decision: .drawCards([DrawnCard(cardID: cardID, source: source)]))
                advanceToNextPlayer()
            } else if canDrawAnotherCard == false {
                logAction(playerID: playerID, decision: .drawCards([DrawnCard(cardID: cardID, source: source)]))
                advanceToNextPlayer()
            } else {
                state = .waitingForPlayer(id: playerID, phase: .drawingSecondCard(firstCardId: cardID, firstDrawSource: source))
            }

        case .waitingForPlayer(let playerID, .drawingSecondCard(let firstCardID, let firstDrawSource)):
            if case .faceUp(let index) = source {
                guard index < faceUpCards.count else {
                    throw PermitModelError.invalidFaceUpIndex
                }
                guard cardsMap[faceUpCards[index]]?.isWild != true else {
                    throw PermitModelError.cannotDrawWildAsSecondCard
                }
            }

            let cardID: CardID = try removeCard(from: source)
            addCardToPlayer(playerID: playerID, cardID: cardID)

            refillFaceUpCards()

            logAction(playerID: playerID, decision: .drawCards([
                DrawnCard(cardID: firstCardID, source: firstDrawSource),
                DrawnCard(cardID: cardID, source: source),
            ]))
            advanceToNextPlayer()

        default:
            throw PermitModelError.notWaitingForPlayerToAct
        }
    }

    // MARK: - Claim Route

    /// Claims a route on the board for the current player by spending matching cards.
    /// - Parameters:
    ///   - routeID: The route to claim.
    ///   - cardIDs: The cards from the player's hand to spend; must match the route length and color requirements.
    /// - Throws: `PermitModelError` if the route is unavailable, cards are invalid, or the player lacks segments.
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

    /// Draws up to three destination permits from the deck for the current player to choose from.
    /// After calling this, the player must call `keepPermits` to complete the action.
    /// - Throws: `PermitModelError` if the game is complete, not in the choosing-action phase, or no permits are available.
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

    /// Keeps the selected permits from a drawn set; the rest are discarded.
    /// Called after `drawPermits` to complete the draw-permits action.
    /// - Parameter permitIDs: The permit IDs to keep from the drawn permits. Must keep at least one.
    /// - Throws: `PermitModelError` if not in the choosing-permits phase or the selection is invalid.
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
            guard drawPile.isEmpty == false else {
                break
            }
            faceUpCards.append(drawPile.removeFirst())
        }
        replaceFaceUpIfNeeded()
        // replaceFaceUpIfNeeded() can leave fewer than 5 when the draw runs out during refill; fill again
        while faceUpCards.count < Self.faceUpCount {
            reshuffleDeckIfNeeded()
            guard !drawPile.isEmpty else { break }
            faceUpCards.append(drawPile.removeFirst())
        }
    }

    mutating func replaceFaceUpIfNeeded() {
        var previousCardSets: [Set<CardID>] = []

        while faceUpCards.filter({ cardsMap[$0]?.isWild == true }).count >= 3 {
            let currentSet: Set<CardID> = Set(faceUpCards)
            if previousCardSets.contains(currentSet) { break }
            previousCardSets.append(currentSet)

            discardPile.append(contentsOf: faceUpCards)
            faceUpCards = []
            for _ in 0..<Self.faceUpCount {
                reshuffleDeckIfNeeded()
                guard !drawPile.isEmpty else { break }
                faceUpCards.append(drawPile.removeFirst())
            }
        }
    }

    private mutating func reshuffleDeckIfNeeded() {
        if drawPile.isEmpty && !discardPile.isEmpty {
            drawPile = discardPile.shuffled()
            discardPile.removeAll()
        }
    }

    private var canDrawAnotherCard: Bool {
        if drawPile.isEmpty == false {
            return true
        }
        if discardPile.isEmpty == false {
            return true
        }
        return faceUpCards.contains { cardsMap[$0]?.isWild != true }
    }

    private func validateCardsForRoute(cardIDs: [CardID], route: Route) throws {
        let cards: [Card] = try cardIDs.map { cardID in
            guard let card = cardsMap[cardID] else {
                throw PermitModelError.cardNotFound
            }
            return card
        }

        let nonWildCards: [Card] = cards.filter { !$0.isWild }

        switch route.color {
        case .any:
            let colors: Set<CardColor> = Set(nonWildCards.map(\.color))
            guard colors.count <= 1 else {
                throw PermitModelError.invalidCardColor
            }
        default:
            let requiredCardColor: CardColor? = routeColorToCardColor(route.color)
            for card in nonWildCards {
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
        refillFaceUpCards()

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
