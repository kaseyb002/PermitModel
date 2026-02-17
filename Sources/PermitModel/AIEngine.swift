import Foundation

public enum AIDifficulty: String, CaseIterable, Codable, Sendable {
    case easy
    case medium
    case hard

    public var displayableName: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
}

public struct AIEngine: Sendable {
    private let difficulty: AIDifficulty

    public init(difficulty: AIDifficulty) {
        self.difficulty = difficulty
    }

    // MARK: - Public API

    /// Returns an action the AI wants to take. The caller is responsible for applying it to the round.
    public func chooseAction(for round: Round, playerID: PlayerID) -> AIAction {
        guard case .waitingForPlayer(let id, let phase) = round.state, id == playerID else {
            return .drawCards(source: .drawPile)
        }

        switch phase {
        case .choosingAction:
            return chooseMainAction(round: round, playerID: playerID)
        case .drawingSecondCard:
            return chooseSecondCardSource(round: round)
        case .choosingPermits(let drawn):
            return .keepPermits(permitIDs: choosePermitsToKeep(drawn: drawn, round: round, playerID: playerID))
        }
    }

    /// Convenience: applies the AI's chosen action directly to the round.
    public func makeMove(on round: inout Round, playerID: PlayerID) throws {
        let action: AIAction = chooseAction(for: round, playerID: playerID)
        try action.apply(to: &round, playerID: playerID)
    }

    // MARK: - Main Action Selection

    private func chooseMainAction(round: Round, playerID: PlayerID) -> AIAction {
        let claimable: [(route: Route, cardIDs: [CardID])] = round.claimableRoutes(for: playerID)

        switch difficulty {
        case .easy:
            return chooseEasyAction(round: round, playerID: playerID, claimable: claimable)
        case .medium:
            return chooseMediumAction(round: round, playerID: playerID, claimable: claimable)
        case .hard:
            return chooseHardAction(round: round, playerID: playerID, claimable: claimable)
        }
    }

    // MARK: - Easy

    private func chooseEasyAction(round: Round, playerID: PlayerID, claimable: [(route: Route, cardIDs: [CardID])]) -> AIAction {
        // Easy: 60% draw cards, 30% claim random claimable route, 10% draw permits
        let roll: Double = Double.random(in: 0..<1)

        if roll < 0.3, let pick = claimable.randomElement() {
            return .claimRoute(routeID: pick.route.id, cardIDs: pick.cardIDs)
        } else if roll < 0.4, !round.permitDeck.isEmpty {
            return .drawPermits
        } else if round.canDrawAnyCard {
            return randomDrawCardAction(round: round)
        } else if let pick = claimable.randomElement() {
            return .claimRoute(routeID: pick.route.id, cardIDs: pick.cardIDs)
        } else if !round.permitDeck.isEmpty {
            return .drawPermits
        } else {
            return randomDrawCardAction(round: round)
        }
    }

    // MARK: - Medium

    private func chooseMediumAction(round: Round, playerID: PlayerID, claimable: [(route: Route, cardIDs: [CardID])]) -> AIAction {
        // Medium: prefer claiming routes that help complete permits, otherwise draw
        let hand: PlayerHand? = round.playerHand(for: playerID)

        // Score each claimable route by whether it helps a permit
        let scored: [(route: Route, cardIDs: [CardID], score: Double)] = claimable.map { entry in
            var score: Double = Double(Route.routeScore(length: entry.route.length))
            if let hand {
                for permit in hand.permits {
                    if routeHelpsPermit(route: entry.route, permit: permit, round: round, playerID: playerID) {
                        score += Double(permit.points)
                    }
                }
            }
            return (route: entry.route, cardIDs: entry.cardIDs, score: score)
        }

        if let best = scored.max(by: { $0.score < $1.score }), best.score > 3 {
            return .claimRoute(routeID: best.route.id, cardIDs: best.cardIDs)
        }

        // If few cards, draw (if any draw is possible)
        if let hand, hand.cards.count < 6, round.canDrawAnyCard {
            return randomDrawCardAction(round: round)
        }

        // Consider drawing permits if we have few
        if let hand, hand.permits.count < 3, !round.permitDeck.isEmpty {
            return .drawPermits
        }

        if round.canDrawAnyCard {
            return randomDrawCardAction(round: round)
        }
        if let pick = claimable.randomElement() {
            return .claimRoute(routeID: pick.route.id, cardIDs: pick.cardIDs)
        }
        if !round.permitDeck.isEmpty {
            return .drawPermits
        }
        return randomDrawCardAction(round: round)
    }

    // MARK: - Hard

    private func chooseHardAction(round: Round, playerID: PlayerID, claimable: [(route: Route, cardIDs: [CardID])]) -> AIAction {
        let hand: PlayerHand? = round.playerHand(for: playerID)

        // Score claimable routes with strategic depth
        let scored: [(route: Route, cardIDs: [CardID], score: Double)] = claimable.map { entry in
            var score: Double = Double(Route.routeScore(length: entry.route.length))

            if let hand {
                // Big bonus for completing a permit connection
                for permit in hand.permits {
                    if routeHelpsPermit(route: entry.route, permit: permit, round: round, playerID: playerID) {
                        score += Double(permit.points) * 2.0
                    }
                    // Check if claiming this route would complete the permit entirely
                    if wouldCompletePermit(route: entry.route, permit: permit, round: round, playerID: playerID) {
                        score += Double(permit.points) * 3.0
                    }
                }

                // Bonus for shorter routes (efficient segment usage)
                if entry.route.length <= 2 {
                    score += 2.0
                }

                // Bonus for blocking double routes in small games
                if round.playerHands.count <= 3, entry.route.doubleRoutePartnerID != nil {
                    score += 3.0
                }
            }

            return (route: entry.route, cardIDs: entry.cardIDs, score: score)
        }

        // Claim if we have a high-scoring option
        if let best = scored.max(by: { $0.score < $1.score }), best.score > 5 {
            return .claimRoute(routeID: best.route.id, cardIDs: best.cardIDs)
        }

        // Draw permits strategically if we have few and the deck has some
        if let hand, hand.permits.count < 3, !round.permitDeck.isEmpty, hand.cards.count >= 4 {
            return .drawPermits
        }

        // Otherwise draw cards if possible, preferring useful colors
        if round.canDrawAnyCard {
            return smartDrawCardAction(round: round, playerID: playerID)
        }
        if let pick = claimable.randomElement() {
            return .claimRoute(routeID: pick.route.id, cardIDs: pick.cardIDs)
        }
        if !round.permitDeck.isEmpty {
            return .drawPermits
        }
        return smartDrawCardAction(round: round, playerID: playerID)
    }

    // MARK: - Permit Selection

    private func choosePermitsToKeep(drawn: [Permit], round: Round, playerID: PlayerID) -> [PermitID] {
        switch difficulty {
        case .easy:
            // Keep 1 random permit
            if let pick = drawn.randomElement() {
                return [pick.id]
            }
            return [drawn[0].id]

        case .medium:
            // Keep permits with lower point values (easier to complete)
            let sorted: [Permit] = drawn.sorted { $0.points < $1.points }
            return [sorted[0].id]

        case .hard:
            // Keep permits that overlap with already-claimed routes
            let claimed: [Route] = round.claimedRoutes(for: playerID)
            let claimedCities: Set<City> = Set(claimed.flatMap { [$0.city1, $0.city2] })

            let scored: [(permit: Permit, score: Double)] = drawn.map { permit in
                var score: Double = 0
                if claimedCities.contains(permit.city1) { score += 10 }
                if claimedCities.contains(permit.city2) { score += 10 }
                // Prefer lower-point permits (easier) unless we have good coverage
                score -= Double(permit.points) * 0.3
                return (permit: permit, score: score)
            }

            // Keep 1 or 2 depending on how good they are
            let sorted: [(permit: Permit, score: Double)] = scored.sorted { $0.score > $1.score }
            if sorted.count >= 2 && sorted[1].score > 5 {
                return [sorted[0].permit.id, sorted[1].permit.id]
            }
            return [sorted[0].permit.id]
        }
    }

    // MARK: - Card Drawing Helpers

    private func randomDrawCardAction(round: Round) -> AIAction {
        // Prefer a non-wild face-up card if available, otherwise draw pile (only if pile has cards)
        let nonWildIndices: [Int] = round.faceUpCards.enumerated().compactMap { index, cardID in
            round.cardsMap[cardID]?.isWild != true ? index : nil
        }
        if let idx = nonWildIndices.randomElement() {
            return .drawCards(source: .faceUp(index: idx))
        }
        if round.canDrawFromPile {
            return .drawCards(source: .drawPile)
        }
        // Pile empty: take any face-up (e.g. wild) if available
        if let idx = round.faceUpCards.indices.randomElement() {
            return .drawCards(source: .faceUp(index: idx))
        }
        return .drawCards(source: .drawPile)
    }

    private func smartDrawCardAction(round: Round, playerID: PlayerID) -> AIAction {
        // Try to draw a face-up card whose color matches unclaimed routes we want
        guard let hand = round.playerHand(for: playerID) else {
            return fallbackDrawCardAction(round: round)
        }

        // Find colors we need for permit-relevant routes
        let neededColors: Set<CardColor> = desiredCardColors(hand: hand, round: round, playerID: playerID)

        // Check face-up cards for a match
        for (index, cardID) in round.faceUpCards.enumerated() {
            guard let card = round.cardsMap[cardID], !card.isWild else { continue }
            if neededColors.contains(card.color) {
                return .drawCards(source: .faceUp(index: index))
            }
        }

        // Check for a wild card (always useful)
        for (index, cardID) in round.faceUpCards.enumerated() {
            if round.cardsMap[cardID]?.isWild == true {
                return .drawCards(source: .faceUp(index: index))
            }
        }

        return fallbackDrawCardAction(round: round)
    }

    /// Returns a valid draw action: draw pile only if it has cards, otherwise a face-up card if any.
    private func fallbackDrawCardAction(round: Round) -> AIAction {
        if round.canDrawFromPile {
            return .drawCards(source: .drawPile)
        }
        if let idx = round.faceUpCards.indices.randomElement() {
            return .drawCards(source: .faceUp(index: idx))
        }
        return .drawCards(source: .drawPile)
    }

    private func chooseSecondCardSource(round: Round) -> AIAction {
        // Can't draw wild as second card from face-up, so pick a non-wild face-up or draw pile
        let nonWildIndices: [Int] = round.faceUpCards.enumerated().compactMap { index, cardID in
            round.cardsMap[cardID]?.isWild != true ? index : nil
        }
        if let idx = nonWildIndices.randomElement() {
            return .drawCards(source: .faceUp(index: idx))
        }
        if round.canDrawFromPile {
            return .drawCards(source: .drawPile)
        }
        // No non-wild face-up and pile empty: take a face-up anyway (will throw cannotDrawWildAsSecondCard in rare edge case)
        if let idx = round.faceUpCards.indices.randomElement() {
            return .drawCards(source: .faceUp(index: idx))
        }
        return .drawCards(source: .drawPile)
    }

    // MARK: - Route Analysis

    private func cardColorForRouteColor(_ routeColor: Route.Color) -> CardColor? {
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

    private func routeHelpsPermit(route: Route, permit: Permit, round: Round, playerID: PlayerID) -> Bool {
        let claimedCities: Set<City> = Set(round.claimedRoutes(for: playerID).flatMap { [$0.city1, $0.city2] })
        let routeCities: Set<City> = [route.city1, route.city2]
        let permitCities: Set<City> = [permit.city1, permit.city2]

        // Route touches at least one permit city, or extends the claimed network toward a permit city
        return !routeCities.isDisjoint(with: permitCities) || !routeCities.isDisjoint(with: claimedCities)
    }

    private func wouldCompletePermit(route: Route, permit: Permit, round: Round, playerID: PlayerID) -> Bool {
        // Simulate claiming this route and check if the permit would be completed
        var testRoutes: [Route] = round.routes
        if let idx = testRoutes.firstIndex(where: { $0.id == route.id }) {
            testRoutes[idx].claimedBy = playerID
        }

        let playerRoutes: [Route] = testRoutes.filter { $0.claimedBy == playerID }
        var adjacency: [City: Set<City>] = [:]
        for r in playerRoutes {
            adjacency[r.city1, default: []].insert(r.city2)
            adjacency[r.city2, default: []].insert(r.city1)
        }

        // BFS from city1 to city2
        var visited: Set<City> = [permit.city1]
        var queue: [City] = [permit.city1]
        while !queue.isEmpty {
            let current: City = queue.removeFirst()
            if current == permit.city2 { return true }
            for neighbor in adjacency[current] ?? [] {
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
        }
        return false
    }

    private func desiredCardColors(hand: PlayerHand, round: Round, playerID: PlayerID) -> Set<CardColor> {
        var colors: Set<CardColor> = []
        let claimedCities: Set<City> = Set(round.claimedRoutes(for: playerID).flatMap { [$0.city1, $0.city2] })

        for route in round.routes where route.claimedBy == nil {
            let routeCities: Set<City> = [route.city1, route.city2]
            // Route is relevant if it touches our network or a permit city
            let permitCities: Set<City> = Set(hand.permits.flatMap { [$0.city1, $0.city2] })
            if !routeCities.isDisjoint(with: claimedCities) || !routeCities.isDisjoint(with: permitCities) {
                if route.color != .any, let cardColor = cardColorForRouteColor(route.color) {
                    colors.insert(cardColor)
                }
            }
        }
        return colors
    }
}

// MARK: - AI Action

public enum AIAction: Equatable, Sendable {
    case drawCards(source: Round.DrawSource)
    case claimRoute(routeID: RouteID, cardIDs: [CardID])
    case drawPermits
    case keepPermits(permitIDs: [PermitID])

    public func apply(to round: inout Round, playerID: PlayerID) throws {
        switch self {
        case .drawCards(let source):
            try round.drawCard(from: source)
        case .claimRoute(let routeID, let cardIDs):
            try round.claimRoute(routeID: routeID, cardIDs: cardIDs)
        case .drawPermits:
            try round.drawPermits()
        case .keepPermits(let permitIDs):
            try round.keepPermits(permitIDs: permitIDs)
        }
    }
}

// MARK: - Round Extension for AI

extension Round {
    /// Convenience: let the AI make a move for the current player.
    public mutating func makeAIMove(difficulty: AIDifficulty) throws {
        guard let playerID = currentPlayerID else {
            throw PermitModelError.notWaitingForPlayerToAct
        }
        let engine: AIEngine = AIEngine(difficulty: difficulty)
        try engine.makeMove(on: &self, playerID: playerID)
    }
}
