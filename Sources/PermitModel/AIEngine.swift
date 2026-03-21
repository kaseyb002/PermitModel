import Foundation

public struct AIEngine: Sendable {
    public init() {}

    // MARK: - Public API

    public func chooseAction(for round: Round, playerID: PlayerID) -> AIAction {
        guard case .waitingForPlayer(let id, let phase) = round.state, id == playerID else {
            return .drawCards(source: .drawPile)
        }

        switch phase {
        case .choosingAction:
            return chooseMainAction(round: round, playerID: playerID)
        case .drawingSecondCard:
            return chooseSecondCardDraw(round: round, playerID: playerID)
        case .choosingPermits(let drawn):
            return .keepPermits(permitIDs: choosePermitsToKeep(drawn: drawn, round: round, playerID: playerID))
        }
    }

    public func chooseInitialPermits(from permits: [Permit], round: Round, playerID: PlayerID) -> [PermitID] {
        guard permits.count >= 2 else {
            return permits.map(\.id)
        }

        let pairs: [(Int, Int)] = permits.count == 3
            ? [(0, 1), (0, 2), (1, 2)]
            : [(0, 1)]

        var bestPairScore: Double = -.infinity
        var bestPairIndices: (Int, Int) = (0, 1)

        for (i, j) in pairs {
            let p1 = permits[i]
            let p2 = permits[j]
            var score: Double = 0

            let cost1 = shortestPathCost(from: p1.city1, to: p1.city2, round: round, playerID: playerID)
            let cost2 = shortestPathCost(from: p2.city1, to: p2.city2, round: round, playerID: playerID)

            if let c1 = cost1, c1 > 0 {
                score += Double(p1.points) / Double(c1) * 10
            }
            if let c2 = cost2, c2 > 0 {
                score += Double(p2.points) / Double(c2) * 10
            }

            if cost1 == nil { score -= 20 }
            if cost2 == nil { score -= 20 }

            let cities1: Set<City> = [p1.city1, p1.city2]
            let cities2: Set<City> = [p2.city1, p2.city2]
            if !cities1.isDisjoint(with: cities2) {
                score += 15
            }

            if score > bestPairScore {
                bestPairScore = score
                bestPairIndices = (i, j)
            }
        }

        return [permits[bestPairIndices.0].id, permits[bestPairIndices.1].id]
    }

    public func makeMove(on round: inout Round, playerID: PlayerID) throws {
        let action = chooseAction(for: round, playerID: playerID)
        try action.apply(to: &round, playerID: playerID)
    }

    // MARK: - Main Decision

    private func chooseMainAction(round: Round, playerID: PlayerID) -> AIAction {
        guard let hand = round.playerHand(for: playerID) else {
            return bestDrawCardAction(round: round, playerID: playerID, desiredColors: [:])
        }

        let claimable = round.claimableRoutes(for: playerID)
        let myRoutes = round.claimedRoutes(for: playerID)
        let targetRoutes = computeTargetRoutes(hand: hand, myRoutes: myRoutes, round: round, playerID: playerID)

        let scored: [(route: Route, cardIDs: [CardID], score: Double)] = claimable.map { entry in
            let score = scoreRoute(
                entry.route,
                targetRoutes: targetRoutes,
                hand: hand,
                myRoutes: myRoutes,
                round: round,
                playerID: playerID
            )
            return (route: entry.route, cardIDs: entry.cardIDs, score: score)
        }

        let best = scored.max(by: { $0.score < $1.score })

        if let best, best.score >= 10.0 {
            return .claimRoute(routeID: best.route.id, cardIDs: best.cardIDs)
        }

        if round.isFinalRound, let best, best.score > 0 {
            return .claimRoute(routeID: best.route.id, cardIDs: best.cardIDs)
        }

        if let best, best.score >= 3.0, hand.cards.count >= 4 {
            return .claimRoute(routeID: best.route.id, cardIDs: best.cardIDs)
        }

        if shouldDrawPermits(hand: hand, myRoutes: myRoutes, round: round, playerID: playerID) {
            return .drawPermits
        }

        let desiredColors = computeDesiredColors(targetRoutes: targetRoutes, allRoutes: round.routes)

        if round.canDrawAnyCard {
            return bestDrawCardAction(round: round, playerID: playerID, desiredColors: desiredColors)
        }

        if let best {
            return .claimRoute(routeID: best.route.id, cardIDs: best.cardIDs)
        }
        if !round.permitDeck.isEmpty {
            return .drawPermits
        }
        return .drawCards(source: .drawPile)
    }

    // MARK: - Path Planning

    /// For each incomplete permit, finds the shortest path of unclaimed routes needed.
    /// Returns a map of routeID → cumulative importance (sum of permit points for each
    /// permit whose plan uses that route).
    private func computeTargetRoutes(
        hand: PlayerHand,
        myRoutes: [Route],
        round: Round,
        playerID: PlayerID
    ) -> [RouteID: Double] {
        var targets: [RouteID: Double] = [:]
        let network = buildAdjacency(from: myRoutes)

        for permit in hand.permits {
            if isConnected(from: permit.city1, to: permit.city2, adjacency: network) {
                continue
            }
            if let path = shortestPath(from: permit.city1, to: permit.city2, round: round, playerID: playerID) {
                for routeID in path {
                    targets[routeID, default: 0] += Double(permit.points)
                }
            }
        }

        return targets
    }

    /// Dijkstra through the board graph.
    /// Already-claimed routes by this player cost 0; unclaimed cost route.length;
    /// routes claimed by opponents are impassable.
    /// Returns the list of unclaimed route IDs the player would need to claim.
    private func shortestPath(
        from start: City,
        to end: City,
        round: Round,
        playerID: PlayerID
    ) -> [RouteID]? {
        struct Edge {
            let routeID: RouteID
            let destination: City
            let cost: Int
            let needsToClaim: Bool
        }

        var graph: [City: [Edge]] = [:]

        for route in round.routes {
            if let claimedBy = route.claimedBy {
                if claimedBy == playerID {
                    let edge = Edge(routeID: route.id, destination: route.city2, cost: 0, needsToClaim: false)
                    let reverse = Edge(routeID: route.id, destination: route.city1, cost: 0, needsToClaim: false)
                    graph[route.city1, default: []].append(edge)
                    graph[route.city2, default: []].append(reverse)
                }
                continue
            }

            if let partnerID = route.doubleRoutePartnerID,
               let partner = round.routes.first(where: { $0.id == partnerID }) {
                if partner.claimedBy == playerID { continue }
                if round.playerHands.count <= 3, partner.claimedBy != nil { continue }
            }

            let edge = Edge(routeID: route.id, destination: route.city2, cost: route.length, needsToClaim: true)
            let reverse = Edge(routeID: route.id, destination: route.city1, cost: route.length, needsToClaim: true)
            graph[route.city1, default: []].append(edge)
            graph[route.city2, default: []].append(reverse)
        }

        var dist: [City: Int] = [start: 0]
        var prev: [City: (city: City, routeID: RouteID, needsToClaim: Bool)] = [:]
        var visited: Set<City> = []
        var queue: [(city: City, cost: Int)] = [(start, 0)]

        while !queue.isEmpty {
            queue.sort { $0.cost < $1.cost }
            let (current, currentCost) = queue.removeFirst()

            if visited.contains(current) { continue }
            visited.insert(current)

            if current == end { break }

            for edge in graph[current] ?? [] {
                let newCost = currentCost + edge.cost
                if newCost < (dist[edge.destination] ?? Int.max) {
                    dist[edge.destination] = newCost
                    prev[edge.destination] = (current, edge.routeID, edge.needsToClaim)
                    queue.append((edge.destination, newCost))
                }
            }
        }

        guard dist[end] != nil else { return nil }

        var routesToClaim: [RouteID] = []
        var city = end
        while city != start {
            guard let previous = prev[city] else { return nil }
            if previous.needsToClaim {
                routesToClaim.append(previous.routeID)
            }
            city = previous.city
        }

        return routesToClaim
    }

    private func shortestPathCost(
        from start: City,
        to end: City,
        round: Round,
        playerID: PlayerID
    ) -> Int? {
        guard let path = shortestPath(from: start, to: end, round: round, playerID: playerID) else {
            return nil
        }
        return path.reduce(0) { sum, routeID in
            sum + (round.routes.first(where: { $0.id == routeID })?.length ?? 0)
        }
    }

    // MARK: - Route Scoring

    private func scoreRoute(
        _ route: Route,
        targetRoutes: [RouteID: Double],
        hand: PlayerHand,
        myRoutes: [Route],
        round: Round,
        playerID: PlayerID
    ) -> Double {
        var score: Double = Double(Route.routeScore(length: route.length))
        let network = buildAdjacency(from: myRoutes)

        for permit in hand.permits {
            if isConnected(from: permit.city1, to: permit.city2, adjacency: network) {
                continue
            }
            if wouldCompletePermit(route: route, permit: permit, myRoutes: myRoutes) {
                score += Double(permit.points) * 5.0
            }
        }

        if let targetScore = targetRoutes[route.id] {
            score += targetScore * 2.0
        }

        let networkCities = Set(myRoutes.flatMap { [$0.city1, $0.city2] })
        if !networkCities.isEmpty {
            let routeCities: Set<City> = [route.city1, route.city2]
            if !routeCities.isDisjoint(with: networkCities) {
                score += 2.0
            } else if targetRoutes[route.id] == nil {
                score -= 3.0
            }
        }

        return score
    }

    // MARK: - Permit Decisions

    private func shouldDrawPermits(
        hand: PlayerHand,
        myRoutes: [Route],
        round: Round,
        playerID: PlayerID
    ) -> Bool {
        guard !round.permitDeck.isEmpty else { return false }
        guard !round.isFinalRound else { return false }

        let network = buildAdjacency(from: myRoutes)
        let allComplete = hand.permits.allSatisfy { permit in
            isConnected(from: permit.city1, to: permit.city2, adjacency: network)
        }

        return allComplete && myRoutes.count >= 3
    }

    private func choosePermitsToKeep(
        drawn: [Permit],
        round: Round,
        playerID: PlayerID
    ) -> [PermitID] {
        guard let hand = round.playerHand(for: playerID) else {
            return [drawn[0].id]
        }

        let myRoutes = round.claimedRoutes(for: playerID)
        let network = buildAdjacency(from: myRoutes)
        let networkCities = Set(myRoutes.flatMap { [$0.city1, $0.city2] })
        let permitCities = Set(hand.permits.flatMap { [$0.city1, $0.city2] })
        let relevantCities = networkCities.union(permitCities)

        let scored: [(permit: Permit, score: Double)] = drawn.map { permit in
            var score: Double = 0

            if isConnected(from: permit.city1, to: permit.city2, adjacency: network) {
                score += Double(permit.points) * 3.0
            }

            if relevantCities.contains(permit.city1) { score += 8 }
            if relevantCities.contains(permit.city2) { score += 8 }

            if let cost = shortestPathCost(from: permit.city1, to: permit.city2, round: round, playerID: playerID),
               cost > 0 {
                score += Double(permit.points) / Double(cost) * 5
            } else if shortestPathCost(from: permit.city1, to: permit.city2, round: round, playerID: playerID) == nil {
                score -= Double(permit.points) * 2.0
            }

            return (permit: permit, score: score)
        }

        let sorted = scored.sorted { $0.score > $1.score }

        var kept: [PermitID] = [sorted[0].permit.id]
        if sorted.count >= 2, sorted[1].score > 5 {
            kept.append(sorted[1].permit.id)
        }

        return kept
    }

    // MARK: - Card Drawing

    private func computeDesiredColors(
        targetRoutes: [RouteID: Double],
        allRoutes: [Route]
    ) -> [CardColor: Double] {
        var colors: [CardColor: Double] = [:]

        for (routeID, importance) in targetRoutes {
            guard let route = allRoutes.first(where: { $0.id == routeID }) else { continue }
            if route.color == .any {
                for color in CardColor.regularColors {
                    colors[color, default: 0] += importance * 0.3
                }
            } else if let cardColor = route.color.cardColor {
                colors[cardColor, default: 0] += importance
            }
        }

        return colors
    }

    private func bestDrawCardAction(
        round: Round,
        playerID: PlayerID,
        desiredColors: [CardColor: Double]
    ) -> AIAction {
        guard round.canDrawAnyCard else {
            return .drawCards(source: .drawPile)
        }

        var usefulCount = 0
        for (_, cardID) in round.faceUpCards.enumerated() {
            guard let card = round.cardsMap[cardID], !card.isWild else { continue }
            if desiredColors[card.color] != nil { usefulCount += 1 }
        }

        if usefulCount < 2 {
            for (index, cardID) in round.faceUpCards.enumerated() {
                if round.cardsMap[cardID]?.isWild == true {
                    return .drawCards(source: .faceUp(index: index))
                }
            }
        }

        var bestIndex: Int?
        var bestScore: Double = 0
        for (index, cardID) in round.faceUpCards.enumerated() {
            guard let card = round.cardsMap[cardID], !card.isWild else { continue }
            if let score = desiredColors[card.color], score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        if let index = bestIndex {
            return .drawCards(source: .faceUp(index: index))
        }

        if round.canDrawFromPile {
            return .drawCards(source: .drawPile)
        }

        if let index = round.faceUpCards.indices.first {
            return .drawCards(source: .faceUp(index: index))
        }

        return .drawCards(source: .drawPile)
    }

    private func chooseSecondCardDraw(round: Round, playerID: PlayerID) -> AIAction {
        guard let hand = round.playerHand(for: playerID) else {
            return fallbackSecondDraw(round: round)
        }

        let myRoutes = round.claimedRoutes(for: playerID)
        let targetRoutes = computeTargetRoutes(hand: hand, myRoutes: myRoutes, round: round, playerID: playerID)
        let desiredColors = computeDesiredColors(targetRoutes: targetRoutes, allRoutes: round.routes)

        var bestIndex: Int?
        var bestScore: Double = 0
        for (index, cardID) in round.faceUpCards.enumerated() {
            guard let card = round.cardsMap[cardID], !card.isWild else { continue }
            if let score = desiredColors[card.color], score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        if let index = bestIndex {
            return .drawCards(source: .faceUp(index: index))
        }

        return fallbackSecondDraw(round: round)
    }

    private func fallbackSecondDraw(round: Round) -> AIAction {
        for (index, cardID) in round.faceUpCards.enumerated() {
            if round.cardsMap[cardID]?.isWild != true {
                return .drawCards(source: .faceUp(index: index))
            }
        }
        if round.canDrawFromPile {
            return .drawCards(source: .drawPile)
        }
        if let index = round.faceUpCards.indices.first {
            return .drawCards(source: .faceUp(index: index))
        }
        return .drawCards(source: .drawPile)
    }

    // MARK: - Graph Utilities

    private func buildAdjacency(from routes: [Route]) -> [City: Set<City>] {
        var adj: [City: Set<City>] = [:]
        for route in routes {
            adj[route.city1, default: []].insert(route.city2)
            adj[route.city2, default: []].insert(route.city1)
        }
        return adj
    }

    private func isConnected(from city1: City, to city2: City, adjacency: [City: Set<City>]) -> Bool {
        if city1 == city2 { return true }
        var visited: Set<City> = [city1]
        var queue: [City] = [city1]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == city2 { return true }
            for neighbor in adjacency[current] ?? [] where !visited.contains(neighbor) {
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return false
    }

    private func wouldCompletePermit(route: Route, permit: Permit, myRoutes: [Route]) -> Bool {
        var adj = buildAdjacency(from: myRoutes)
        adj[route.city1, default: []].insert(route.city2)
        adj[route.city2, default: []].insert(route.city1)
        return isConnected(from: permit.city1, to: permit.city2, adjacency: adj)
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
    public mutating func makeAIMove() throws {
        guard let playerID = currentPlayerID else {
            throw PermitModelError.notWaitingForPlayerToAct
        }
        try AIEngine().makeMove(on: &self, playerID: playerID)
    }
}
