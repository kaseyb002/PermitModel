import Foundation

extension Round {
    public static func fake(
        id: String = UUID().uuidString,
        started: Date = .now,
        cookedDeck: [Card]? = nil,
        cookedPermits: [Permit]? = nil,
        gameMap: GameMap = .standard(),
        players: [Player] = [
            .fake(name: "Player 1", color: .blue),
            .fake(name: "Player 2", color: .red),
        ],
        segmentsPerPlayer: Int = Round.initialSegments
    ) throws -> Round {
        try Round(
            id: id,
            started: started,
            cookedDeck: cookedDeck,
            cookedPermits: cookedPermits,
            gameMap: gameMap,
            players: players,
            segmentsPerPlayer: segmentsPerPlayer
        )
    }

    /// A completed two-player game on the standard map.
    ///
    /// - Alice (blue, 60 pts): Helena→Denver→SantaFe→Phoenix→LA→SF→Portland→Seattle
    ///   – all three permits completed, 2 segments remaining (triggered final round)
    /// - Bob (red, 39 pts): Boston→Montreal→Toronto→Chicago→StLouis→Nashville→Atlanta→Raleigh→Washington→NY
    ///   – 2/3 permits completed, longest-path bonus (+10)
    public static func fakeCompleted(
        id: String = "completed-game",
        started: Date = Date(timeIntervalSinceNow: -3600)
    ) throws -> Round {
        let p1 = Player.fake(id: "p1", name: "Alice", color: .blue)
        let p2 = Player.fake(id: "p2", name: "Bob", color: .red)

        let cookedPermits: [Permit] = [
            // P1 initial permits (first 3 dealt)
            Permit(id: 30, city1: .seattle, city2: .losAngeles, points: 9),
            Permit(id: 9, city1: .portland, city2: .phoenix, points: 11),
            Permit(id: 26, city1: .helena, city2: .losAngeles, points: 8),
            // P2 initial permits (next 3 dealt)
            Permit(id: 23, city1: .montreal, city2: .atlanta, points: 9),
            Permit(id: 4, city1: .newYork, city2: .atlanta, points: 6),
            Permit(id: 21, city1: .boston, city2: .miami, points: 12),
            // Remaining deck
            Permit(id: 1, city1: .losAngeles, city2: .newYork, points: 21),
            Permit(id: 2, city1: .duluth, city2: .houston, points: 8),
        ]

        var round = try Round(
            id: id,
            started: started,
            cookedPermits: cookedPermits,
            players: [p1, p2],
            segmentsPerPlayer: 23
        )

        // Complete setup: both players keep all initial permits
        try round.selectInitialPermits(playerID: p1.id, permitIDs: [30, 9, 26])
        try round.selectInitialPermits(playerID: p2.id, permitIDs: [23, 4, 21])

        // --- Mutate directly to a completed game state ---

        // P1 routes: Helena→Denver→SantaFe→Phoenix→LA→SF→Portland→Seattle (21 segments)
        let p1RouteIDs: Set<RouteID> = [7, 10, 59, 62, 64, 54, 14]
        for i in round.routes.indices where p1RouteIDs.contains(round.routes[i].id) {
            round.routes[i].claimedBy = p1.id
        }

        // P2 routes: Boston→Montreal→Toronto→Chicago→StLouis→Nashville→Atlanta→Raleigh→Washington→NY (22 segments)
        let p2RouteIDs: Set<RouteID> = [25, 26, 44, 72, 78, 82, 80, 35, 31, 28]
        for i in round.routes.indices where p2RouteIDs.contains(round.routes[i].id) {
            round.routes[i].claimedBy = p2.id
        }

        // Tally route scores and segments
        var p1RouteScore = 0, p1Segments = 0
        var p2RouteScore = 0, p2Segments = 0
        for route in round.routes {
            if route.claimedBy == p1.id {
                p1RouteScore += Route.routeScore(length: route.length)
                p1Segments += route.length
            } else if route.claimedBy == p2.id {
                p2RouteScore += Route.routeScore(length: route.length)
                p2Segments += route.length
            }
        }

        round.playerHands[0].remainingSegments -= p1Segments
        round.playerHands[1].remainingSegments -= p2Segments
        round.playerHands[0].player.score = p1RouteScore
        round.playerHands[1].player.score = p2RouteScore

        // Permit bonuses/penalties (same logic as endGame)
        for i in round.playerHands.indices {
            for permit in round.playerHands[i].permits {
                if round.isPermitCompleted(permit: permit, playerID: round.playerHands[i].player.id) {
                    round.playerHands[i].player.score += permit.points
                } else {
                    round.playerHands[i].player.score -= permit.points
                }
            }
        }

        // Longest continuous path bonus (+10)
        let longestPathPlayers = round.playersWithLongestPath()
        for i in round.playerHands.indices {
            if longestPathPlayers.contains(round.playerHands[i].player.id) {
                round.playerHands[i].player.score += 10
            }
        }

        // Redistribute cards to reflect a finished game
        var pool = round.playerHands[0].cards + round.playerHands[1].cards + round.drawPile
        round.playerHands[0].cards = Array(pool.prefix(2))
        pool.removeFirst(2)
        round.playerHands[1].cards = Array(pool.prefix(3))
        pool.removeFirst(3)
        let discardCount = p1Segments + p2Segments
        round.discardPile = Array(pool.prefix(discardCount))
        pool.removeFirst(min(discardCount, pool.count))
        round.drawPile = pool

        round.finalRoundTriggeredBy = p1.id
        round.turnsRemainingInFinalRound = 0

        // Representative action log
        round.log = [
            .init(playerID: p1.id, decision: .drawCards([
                .init(cardID: "blue-1", source: .drawPile),
                .init(cardID: "green-1", source: .drawPile),
            ]), timestamp: started.addingTimeInterval(120)),
            .init(playerID: p2.id, decision: .drawCards([
                .init(cardID: "red-1", source: .drawPile),
                .init(cardID: "orange-1", source: .faceUp(index: 0)),
            ]), timestamp: started.addingTimeInterval(180)),
            .init(playerID: p1.id, decision: .claimRoute(
                routeId: 7, cardIds: ["purple-1"], points: 1
            ), timestamp: started.addingTimeInterval(300)),
            .init(playerID: p2.id, decision: .claimRoute(
                routeId: 28, cardIds: ["red-2", "red-3"], points: 2
            ), timestamp: started.addingTimeInterval(420)),
            .init(playerID: p1.id, decision: .claimRoute(
                routeId: 59, cardIds: ["yellow-1", "yellow-2", "yellow-3"], points: 4
            ), timestamp: started.addingTimeInterval(900)),
            .init(playerID: p2.id, decision: .claimRoute(
                routeId: 26, cardIds: ["white-1", "white-2", "white-3", "white-4"], points: 7
            ), timestamp: started.addingTimeInterval(1200)),
            .init(playerID: p1.id, decision: .claimRoute(
                routeId: 10, cardIds: ["green-2", "green-3", "green-4", "green-5", "green-6"], points: 10
            ), timestamp: started.addingTimeInterval(1800)),
            .init(playerID: p2.id, decision: .drawPermits(
                keptPermitIds: [1]
            ), timestamp: started.addingTimeInterval(2100)),
            .init(playerID: p1.id, decision: .claimRoute(
                routeId: 14, cardIds: ["green-7", "green-8", "green-9", "green-10"], points: 7
            ), timestamp: started.addingTimeInterval(3000)),
            .init(playerID: p2.id, decision: .claimRoute(
                routeId: 44, cardIds: ["green-11", "green-12"], points: 2
            ), timestamp: started.addingTimeInterval(3300)),
        ]

        // Determine winner (same tiebreaker logic as endGame)
        let winner = round.playerHands.max(by: { a, b in
            if a.player.score == b.player.score {
                let aC = a.permits.filter { round.isPermitCompleted(permit: $0, playerID: a.player.id) }.count
                let bC = b.permits.filter { round.isPermitCompleted(permit: $0, playerID: b.player.id) }.count
                return aC < bC
            }
            return a.player.score < b.player.score
        })!.player

        round.state = .gameComplete(winner: winner)
        round.ended = started.addingTimeInterval(3600)

        return round
    }
}
