import Foundation

// MARK: - AIEngineSimple

/// Straightforward AI focused on hand size (“fiber cards”), segments (“remaining fibers”), and
/// routes that connect incomplete permits. Does not use difficulty tiers and never draws new permits.
public struct AIEngineSimple: Sendable {

    public init() {}

    // MARK: Public API

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
            return .keepPermits(permitIDs: choosePermitsAfterDraw(drawn: drawn, round: round, playerID: playerID))
        }
    }

    public func chooseInitialPermits(from permits: [Permit], round: Round, playerID: PlayerID) -> [PermitID] {
        guard permits.count >= Round.minInitialPermitsToKeep else {
            return permits.map(\.id)
        }

        let k = Round.minInitialPermitsToKeep
        var bestIDs: [PermitID] = []
        var bestOverlap = -1

        func enumerateCombinations(_ start: Int, _ chosen: [Int]) {
            if chosen.count == k {
                let cities = chosen.flatMap { [permits[$0].city1, permits[$0].city2] }
                let unique = Set(cities)
                let overlapScore = cities.count - unique.count
                if overlapScore > bestOverlap {
                    bestOverlap = overlapScore
                    bestIDs = chosen.map { permits[$0].id }
                }
                return
            }
            for i in start..<permits.count {
                if chosen.count + (permits.count - i) < k { break }
                enumerateCombinations(i + 1, chosen + [i])
            }
        }

        enumerateCombinations(0, [])
        return bestIDs.isEmpty ? Array(permits.prefix(k).map(\.id)) : bestIDs
    }

    public func makeMove(on round: inout Round, playerID: PlayerID) throws {
        let action = chooseAction(for: round, playerID: playerID)
        try action.apply(to: &round, playerID: playerID)
    }

    // MARK: - Connecting routes & fiber needs (public for reuse / tests)

    /// Unclaimed routes that lie on a shortest (by segment count) path for at least one **incomplete** permit.
    public func myConnectingRoutes(round: Round, playerID: PlayerID) -> [Route] {
        guard let hand = round.playerHand(for: playerID) else { return [] }
        let myRoutes = round.claimedRoutes(for: playerID)
        let adj = buildAdjacency(from: myRoutes)

        var seen: Set<RouteID> = []
        var result: [Route] = []

        for permit in hand.permits {
            if isConnected(from: permit.city1, to: permit.city2, adjacency: adj) { continue }
            guard let pathIDs = shortestPathUnclaimedRouteIDs(
                from: permit.city1,
                to: permit.city2,
                round: round,
                playerID: playerID
            ) else { continue }
            for rid in pathIDs {
                if seen.insert(rid).inserted, let r = round.routes.first(where: { $0.id == rid }) {
                    result.append(r)
                }
            }
        }

        return result
    }

    /// Rough shortfall of train-card colors still needed to cover `myConnectingRoutes()`, after
    /// counting the current hand (wilds absorb the largest gaps). Keys are only colors with positive need.
    public func neededFiberCards(round: Round, playerID: PlayerID) -> [CardColor: Int] {
        guard let hand = round.playerHand(for: playerID) else { return [:] }
        let handCards: [Card] = hand.cards.compactMap { round.cardsMap[$0] }

        var demand: [CardColor: Int] = [:]
        let routes = myConnectingRoutes(round: round, playerID: playerID).filter { $0.claimedBy == nil }

        for route in routes {
            switch route.color {
            case .any:
                let share = (route.length + CardColor.regularColors.count - 1) / CardColor.regularColors.count
                for c in CardColor.regularColors {
                    demand[c, default: 0] += max(1, share)
                }
            default:
                if let cc = route.color.cardColor {
                    demand[cc, default: 0] += route.length
                }
            }
        }

        var deficit: [CardColor: Int] = demand
        var wilds = 0
        for card in handCards {
            if card.isWild {
                wilds += 1
            } else {
                let c = card.color
                deficit[c, default: 0] = max(0, (deficit[c] ?? 0) - 1)
            }
        }

        while wilds > 0 {
            let colors = CardColor.regularColors
            let target = colors.max { (deficit[$0] ?? 0) < (deficit[$1] ?? 0) }!
            let v = deficit[target] ?? 0
            if v <= 0 { break }
            deficit[target] = v - 1
            wilds -= 1
        }

        return deficit.filter { $0.value > 0 }
    }

    // MARK: - Main turn

    private func chooseMainAction(round: Round, playerID: PlayerID) -> AIAction {
        guard let hand = round.playerHand(for: playerID) else {
            return fallbackDraw(round: round)
        }

        let cardCount = hand.cards.count
        let segments = hand.remainingSegments
        let permitsDone = hand.permits.allSatisfy { round.isPermitCompleted(permit: $0, playerID: playerID) }

        // Stock up on train cards while we have segments to spend and the hand is still small.
        if cardCount < 12, segments > 12, round.canDrawAnyCard {
            return bestFiberDraw(round: round, playerID: playerID, phase: .first)
        }

        // Otherwise try to claim.
        let claimable = round.claimableRoutes(for: playerID)
        if let best = pickClaim(
            from: claimable,
            round: round,
            playerID: playerID,
            permitsAllFulfilled: permitsDone,
            segmentsRemaining: segments
        ) {
            return .claimRoute(routeID: best.route.id, cardIDs: best.cardIDs)
        }

        if round.canDrawAnyCard {
            return bestFiberDraw(round: round, playerID: playerID, phase: .first)
        }

        return .drawCards(source: .drawPile)
    }

    private func chooseSecondCardDraw(round: Round, playerID: PlayerID) -> AIAction {
        bestFiberDraw(round: round, playerID: playerID, phase: .second)
    }

    private enum DrawPhase { case first, second }

    private func bestFiberDraw(round: Round, playerID: PlayerID, phase: DrawPhase) -> AIAction {
        guard round.canDrawAnyCard else { return .drawCards(source: .drawPile) }

        let need = neededFiberCards(round: round, playerID: playerID)
        let desired: [CardColor: Double] = need.mapValues { Double($0) }

        if phase == .first {
            let useful = round.faceUpCards.compactMap { round.cardsMap[$0] }.filter {
                !$0.isWild && (desired[$0.color] ?? 0) > 0
            }.count
            if useful < 2, let idx = round.faceUpCards.firstIndex(where: { round.cardsMap[$0]?.isWild == true }) {
                return .drawCards(source: .faceUp(index: idx))
            }
        }

        var bestIndex: Int?
        var bestScore: Double = -1
        for (index, cardID) in round.faceUpCards.enumerated() {
            guard let card = round.cardsMap[cardID] else { continue }
            if card.isWild {
                if phase == .second { continue }
                continue
            }
            let score = desired[card.color] ?? 0
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        if let index = bestIndex, bestScore > 0 {
            return .drawCards(source: .faceUp(index: index))
        }

        if round.canDrawFromPile {
            return .drawCards(source: .drawPile)
        }

        for (index, cardID) in round.faceUpCards.enumerated() {
            if round.cardsMap[cardID]?.isWild == true, phase == .second { continue }
            return .drawCards(source: .faceUp(index: index))
        }

        return .drawCards(source: .drawPile)
    }

    private func fallbackDraw(round: Round) -> AIAction {
        round.canDrawFromPile ? .drawCards(source: .drawPile) : .drawCards(source: .faceUp(index: 0))
    }

    private func pickClaim(
        from claimable: [(route: Route, cardIDs: [CardID])],
        round: Round,
        playerID: PlayerID,
        permitsAllFulfilled: Bool,
        segmentsRemaining: Int
    ) -> (route: Route, cardIDs: [CardID])? {
        guard !claimable.isEmpty else { return nil }

        let cardCount = round.playerHand(for: playerID)?.cards.count ?? 0
        let connectingIDs = Set(myConnectingRoutes(round: round, playerID: playerID).map(\.id))
        let myRoutes = round.claimedRoutes(for: playerID)
        let network = Set(myRoutes.flatMap { [$0.city1, $0.city2] })

        func score(_ entry: (route: Route, cardIDs: [CardID])) -> Int {
            let route = entry.route
            let touchesNetwork = network.contains(route.city1) || network.contains(route.city2)
            let onConnectingPlan = connectingIDs.contains(route.id)

            var s = Route.routeScore(length: route.length) * 2

            if permitsAllFulfilled {
                if touchesNetwork { s += 500 }
                return s
            }

            // Endgame: few segments left — push unfinished permits, else extend network.
            if segmentsRemaining < 12 {
                if onConnectingPlan { s += 600 }
                if touchesNetwork { s += 300 }
                return s
            }

            // Plenty of segments left: prefer claiming once the hand is full enough.
            if cardCount >= 12 {
                if onConnectingPlan, touchesNetwork { s += 800 }
                else if onConnectingPlan { s += 500 }
                else if touchesNetwork { s += 200 }
            } else {
                // Usually drawing; only scores if we had to fall back to claim.
                if onConnectingPlan, touchesNetwork { s += 400 }
                else if onConnectingPlan { s += 250 }
            }

            return s
        }

        return claimable.max(by: { score($0) < score($1) })
    }

    /// After an opponent or flow forces a permit draw: keep a single strong ticket (never “no permits”).
    private func choosePermitsAfterDraw(drawn: [Permit], round: Round, playerID: PlayerID) -> [PermitID] {
        guard round.playerHand(for: playerID) != nil else {
            return [drawn[0].id]
        }
        let myRoutes = round.claimedRoutes(for: playerID)
        let network = Set(myRoutes.flatMap { [$0.city1, $0.city2] })

        let scored = drawn.map { permit -> (Permit, Int) in
            var s = permit.points * 3
            if network.contains(permit.city1) { s += 5 }
            if network.contains(permit.city2) { s += 5 }
            return (permit, s)
        }
        let best = scored.max(by: { $0.1 < $1.1 })!.0
        return [best.id]
    }

    // MARK: - Shortest path (segment count)

    private func shortestPathUnclaimedRouteIDs(
        from start: City,
        to end: City,
        round: Round,
        playerID: PlayerID
    ) -> Set<RouteID>? {
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
                    graph[route.city1, default: []].append(Edge(routeID: route.id, destination: route.city2, cost: 0, needsToClaim: false))
                    graph[route.city2, default: []].append(Edge(routeID: route.id, destination: route.city1, cost: 0, needsToClaim: false))
                }
                continue
            }
            if let partnerID = route.doubleRoutePartnerID,
               let partner = round.routes.first(where: { $0.id == partnerID }) {
                if partner.claimedBy == playerID { continue }
                if round.playerHands.count <= 3, partner.claimedBy != nil { continue }
            }

            let cost = route.length
            graph[route.city1, default: []].append(Edge(routeID: route.id, destination: route.city2, cost: cost, needsToClaim: true))
            graph[route.city2, default: []].append(Edge(routeID: route.id, destination: route.city1, cost: cost, needsToClaim: true))
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

        var ids: Set<RouteID> = []
        var city = end
        while city != start {
            guard let step = prev[city] else { return nil }
            if step.needsToClaim { ids.insert(step.routeID) }
            city = step.city
        }
        return ids
    }

    // MARK: - Graph

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
            let c = queue.removeFirst()
            if c == city2 { return true }
            for n in adjacency[c] ?? [] where !visited.contains(n) {
                visited.insert(n)
                queue.append(n)
            }
        }
        return false
    }
}

// MARK: - Round

extension Round {
    /// Single-player “simple” AI: overlap permits, hoard cards toward connecting routes, claim when stocked or low on segments; never draws new permits by choice.
    public mutating func makeAIMoveSimple() throws {
        guard let playerID = currentPlayerID else {
            throw PermitModelError.notWaitingForPlayerToAct
        }
        try AIEngineSimple().makeMove(on: &self, playerID: playerID)
    }
}
