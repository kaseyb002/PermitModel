import Foundation

// MARK: - AIEngineExtreme

/// Heavier AI policy with rollout-based lookahead on close decisions. For the plan-aligned
/// heuristic engine, use `AIEngine`.
public struct AIEngineExtreme: Sendable {
    public let difficulty: AIDifficulty
    public let visibility: AIVisibility
    /// Rollout budget per candidate when lookahead is enabled. Low values keep per-move latency under a few hundred ms.
    public let rolloutsPerCandidate: Int
    public let lookaheadCandidateCount: Int

    public init(
        difficulty: AIDifficulty = .hard,
        visibility: AIVisibility? = nil,
        rolloutsPerCandidate: Int = 6,
        lookaheadCandidateCount: Int = 3
    ) {
        self.difficulty = difficulty
        self.visibility = visibility ?? difficulty.defaultVisibility
        self.rolloutsPerCandidate = rolloutsPerCandidate
        self.lookaheadCandidateCount = lookaheadCandidateCount
    }

    // MARK: Public API

    public func chooseAction(for round: Round, playerID: PlayerID) -> AIAction {
        guard case .waitingForPlayer(let id, let phase) = round.state, id == playerID else {
            return .drawCards(source: .drawPile)
        }

        switch phase {
        case .choosingAction:
            if difficulty == .easy {
                return legacyChooseMainAction(round: round, playerID: playerID)
            }
            return chooseMainAction(round: round, playerID: playerID)
        case .drawingSecondCard:
            return chooseSecondCardDraw(round: round, playerID: playerID)
        case .choosingPermits(let drawn):
            return .keepPermits(permitIDs: choosePermitsToKeep(drawn: drawn, round: round, playerID: playerID))
        }
    }

    public func chooseInitialPermits(from permits: [Permit], round: Round, playerID: PlayerID) -> [PermitID] {
        guard permits.count >= Round.minInitialPermitsToKeep else {
            return permits.map(\.id)
        }

        // Score every subset of size >= minInitialPermitsToKeep. With 3 permits drawn and minimum 2
        // this is a cheap enumeration; generalized for robustness if the draw size changes later.
        let minCount = Round.minInitialPermitsToKeep
        let subsets: [[Int]] = allSubsets(count: permits.count, minSize: minCount)

        var bestScore: Double = -.infinity
        var bestSubset: [Int] = Array(0..<minCount)

        for subset in subsets {
            let score = scoreInitialPermitSubset(indices: subset, permits: permits, round: round, playerID: playerID)
            if score > bestScore {
                bestScore = score
                bestSubset = subset
            }
        }

        return bestSubset.map { permits[$0].id }
    }

    public func makeMove(on round: inout Round, playerID: PlayerID) throws {
        let action = chooseAction(for: round, playerID: playerID)
        try action.apply(to: &round, playerID: playerID)
    }

    // MARK: - Utility Policy (medium + hard)

    /// Unified decision: compute expected utility for claim, draw-cards, and draw-permits,
    /// then pick the highest. Hard difficulty adds a rollout re-ranking on the top-K candidates.
    private func chooseMainAction(round: Round, playerID: PlayerID) -> AIAction {
        guard let hand = round.playerHand(for: playerID) else {
            return bestDrawCardAction(round: round, playerID: playerID, desiredColors: [:], phase: .first)
        }

        let ctx = DecisionContext(round: round, playerID: playerID, hand: hand, engine: self)
        var candidates: [ScoredAction] = []

        // 1) Every claimable route is a candidate.
        let claimable = round.claimableRoutes(for: playerID)
        for entry in claimable {
            let utility = claimUtility(route: entry.route, cardIDs: entry.cardIDs, ctx: ctx)
            candidates.append(ScoredAction(
                action: .claimRoute(routeID: entry.route.id, cardIDs: entry.cardIDs),
                score: utility
            ))
        }

        // 2) Drawing cards (value of improving colors toward near-claimable routes).
        if round.canDrawAnyCard {
            let desiredColors = ctx.desiredColors
            let drawAction = bestDrawCardAction(round: round, playerID: playerID, desiredColors: desiredColors, phase: .first)
            let drawUtility = drawCardsUtility(ctx: ctx)
            candidates.append(ScoredAction(action: drawAction, score: drawUtility))
        }

        // 3) Drawing permits (expected value of kept permits minus turn cost and failure risk).
        if !round.permitDeck.isEmpty {
            let permitsUtility = drawPermitsUtility(ctx: ctx)
            candidates.append(ScoredAction(action: .drawPermits, score: permitsUtility))
        }

        candidates.sort { $0.score > $1.score }

        // Final-round safety: if we're in the final round, never draw permits and claim aggressively
        // over drawing unless drawing strictly beats every claim.
        if round.isFinalRound {
            candidates.removeAll { if case .drawPermits = $0.action { return true } else { return false } }
        }

        guard !candidates.isEmpty else {
            return .drawCards(source: .drawPile)
        }

        // Lookahead re-ranking on top-K candidates. Skip when the heuristic top is a clear winner —
        // rollouts are noisy and mostly useful for tie-breaking between comparable options.
        if difficulty.usesLookahead, candidates.count > 1 {
            let top = candidates[0].score
            let second = candidates[1].score
            if abs(top - second) > 8 {
                return candidates.first!.action
            }
            return rerankWithRollouts(candidates: candidates, round: round, playerID: playerID)
        }

        return candidates.first!.action
    }

    // MARK: - Claim Utility

    private func claimUtility(route: Route, cardIDs: [CardID], ctx: DecisionContext) -> Double {
        var score = Double(Route.routeScore(length: route.length))

        // Permit impact: completion flips −p to +p (2p swing); progress contributes proportionally.
        score += permitImpact(route: route, ctx: ctx)

        // Longest-continuous-path bonus (+10 at game end). Weight higher when fewer turns remain.
        let lpDelta = longestPathDelta(route: route, ctx: ctx)
        score += Double(lpDelta) * longestPathWeight(ctx: ctx)

        // Contention: taking a route an opponent can plausibly reach has extra value.
        score += contentionBonus(route: route, ctx: ctx)

        // Blocking: hard difficulty sees opponent permits and can evaluate denial value.
        score += blockingBonus(route: route, ctx: ctx)

        // Opportunity cost: spending cards on a route that doesn't advance any plan is wasteful.
        score -= opportunityCost(route: route, cardIDs: cardIDs, ctx: ctx)

        // Slight synergy bonus for staying connected to our own existing network.
        let networkCities = ctx.myNetworkCities
        if !networkCities.isEmpty {
            let routeCities: Set<City> = [route.city1, route.city2]
            if !routeCities.isDisjoint(with: networkCities) {
                score += 1.0
            }
        }

        return score
    }

    /// Expected contribution of this claim to the final +/- permit accounting.
    private func permitImpact(route: Route, ctx: DecisionContext) -> Double {
        var total: Double = 0
        let adj = ctx.myAdjacency

        for permit in ctx.hand.permits {
            if isConnected(from: permit.city1, to: permit.city2, adjacency: adj) {
                continue
            }
            if wouldCompletePermit(route: route, permit: permit, myRoutes: ctx.myRoutes) {
                // 2p swing: failing −p → completed +p.
                total += 2.0 * Double(permit.points)
                continue
            }
            guard let plan = ctx.planFor(permit: permit) else { continue }
            if plan.edgeIDs.contains(route.id) {
                let remaining = max(1, plan.remainingSegmentCost)
                let progress = Double(route.length) / Double(remaining)
                total += Double(permit.points) * progress * 0.9
            }
        }

        return total
    }

    /// Fast directional approximation of the longest-continuous-path delta.
    ///
    /// A real longest-simple-path is NP-hard, and the exact DFS in `longestContinuousPathLength`
    /// is called by `Round+Scoring` at game end on a single graph; calling it per candidate route
    /// for every decision would dominate the turn budget. This cheap heuristic captures the
    /// strategically relevant cases: extending an existing network endpoint by `route.length`
    /// vs. disconnected spurs or cycle-forming routes (neither of which reliably extends the
    /// longest path). It is intentionally conservative — the rollout phase in hard mode
    /// compensates by actually playing games out.
    private func longestPathDelta(route: Route, ctx: DecisionContext) -> Int {
        let c1InNet = ctx.myNetworkCities.contains(route.city1)
        let c2InNet = ctx.myNetworkCities.contains(route.city2)
        if c1InNet != c2InNet {
            return route.length
        }
        if !c1InNet && !c2InNet {
            // Disjoint chunk — we'll try to connect later; give half credit so chains still form.
            return route.length / 2
        }
        // Both endpoints already in the network: forms a cycle; doesn't help longest simple path.
        return 0
    }

    /// Weight scales with how soon the game ends. In the final round the +10 is near-certain to land;
    /// early game the expected contribution of a single segment extension is smaller.
    private func longestPathWeight(ctx: DecisionContext) -> Double {
        if ctx.round.isFinalRound { return 1.0 }
        let totalSegments = Double(ctx.round.playerHands.map(\.remainingSegments).max() ?? Round.initialSegments)
        if totalSegments <= 0 { return 1.0 }
        // Fraction of the game remaining; weight eases from ~0.15 early to ~0.6 late.
        let remaining = totalSegments / Double(Round.initialSegments)
        return max(0.15, 1.0 - remaining * 0.7)
    }

    /// Small bonus for grabbing a route an opponent's network is adjacent to (public info only).
    private func contentionBonus(route: Route, ctx: DecisionContext) -> Double {
        guard difficulty.usesUtilityPolicy else { return 0 }
        let opponents = ctx.round.playerHands.map(\.player.id).filter { $0 != ctx.playerID }
        var pressure: Double = 0
        for opp in opponents {
            let theirCities = Set(ctx.round.claimedRoutes(for: opp).flatMap { [$0.city1, $0.city2] })
            if theirCities.contains(route.city1) || theirCities.contains(route.city2) {
                pressure += 1.0
            }
        }
        // If this is half of a double route and the other half is claimed, denying it is nice.
        if let partnerID = route.doubleRoutePartnerID,
           let partner = ctx.round.routes.first(where: { $0.id == partnerID }),
           partner.claimedBy != nil, partner.claimedBy != ctx.playerID {
            pressure += 1.0
        }
        return pressure * 1.5
    }

    /// Looks up a precomputed per-route blocking value built once in `DecisionContext.init`.
    /// See `DecisionContext` for how opponent plans are folded into this table.
    private func blockingBonus(route: Route, ctx: DecisionContext) -> Double {
        ctx.blockingValuePerRoute[route.id] ?? 0
    }

    private func opportunityCost(route: Route, cardIDs: [CardID], ctx: DecisionContext) -> Double {
        // Punish spending cards that don't advance any plan. Amount scales with wilds burned.
        let onPlan = ctx.anyPlanContains(routeID: route.id)
        let completesSomething = ctx.hand.permits.contains { permit in
            !ctx.isPermitSatisfied(permit) &&
            wouldCompletePermit(route: route, permit: permit, myRoutes: ctx.myRoutes)
        }
        if onPlan || completesSomething { return 0 }

        let wildCount = cardIDs.reduce(0) { acc, id in
            acc + (ctx.round.cardsMap[id]?.isWild == true ? 1 : 0)
        }
        // Length 1-2 off-plan routes with wilds: heavy penalty. Otherwise mild.
        let baseline = Double(route.length) * 0.8
        let wildPenalty = Double(wildCount) * 2.5
        return baseline + wildPenalty
    }

    // MARK: - Draw-Cards Utility

    /// Rough expected value of a two-card draw in terms of route score it unlocks next turn.
    private func drawCardsUtility(ctx: DecisionContext) -> Double {
        let hand = ctx.hand
        let round = ctx.round
        let handCards: [Card] = hand.cards.compactMap { round.cardsMap[$0] }

        // Baseline: keep playing. Cap near the expected value of 2 well-directed draws (~2 cards * points/card).
        var best: Double = 2.0

        let myAdj = ctx.myAdjacency
        for route in round.routes where route.claimedBy == nil {
            if hand.remainingSegments < route.length { continue }
            if let partnerID = route.doubleRoutePartnerID,
               let partner = round.routes.first(where: { $0.id == partnerID }) {
                if partner.claimedBy == ctx.playerID { continue }
                if round.playerHands.count <= 3, partner.claimedBy != nil { continue }
            }

            let deficit = colorDeficit(route: route, handCards: handCards)
            if deficit > 3 { continue } // unreachable within a handful of draws

            let onPlan = ctx.anyPlanContains(routeID: route.id)
            let wouldComplete = hand.permits.contains { permit in
                !isConnected(from: permit.city1, to: permit.city2, adjacency: myAdj) &&
                wouldCompletePermit(route: route, permit: permit, myRoutes: ctx.myRoutes)
            }

            guard onPlan || wouldComplete else { continue }

            let expectedTurnsToDraw = Double(max(1, deficit)) * 0.6 // each 2-card draw averages ~1 useful card
            let futureBase = Double(Route.routeScore(length: route.length))
            let futurePermit = wouldComplete ? Double(hand.permits.filter { wouldCompletePermit(route: route, permit: $0, myRoutes: ctx.myRoutes) }.map(\.points).reduce(0, +)) * 1.8 : 0
            let candidateValue = (futureBase + futurePermit) / max(1.0, expectedTurnsToDraw)
            if candidateValue > best { best = candidateValue }
        }

        // If we have plenty of face-up wilds we love, small bump.
        let faceUpWilds = round.faceUpCards.compactMap { round.cardsMap[$0] }.filter(\.isWild).count
        if faceUpWilds > 0 { best += 1.0 }

        return best * 0.8
    }

    // MARK: - Draw-Permits Utility

    private func drawPermitsUtility(ctx: DecisionContext) -> Double {
        guard !ctx.round.permitDeck.isEmpty else { return 0 }
        if ctx.round.isFinalRound { return -100 }

        // Rough expectation: best kept permit is around the average permit value; failure risk
        // scales with how little room we have left.
        let deck = ctx.round.permitDeck
        let avgPermit = deck.isEmpty ? 8.0 : Double(deck.map(\.points).reduce(0, +)) / Double(deck.count)

        let remainingSegments = ctx.hand.remainingSegments
        let incompleteCost = ctx.hand.permits
            .filter { !ctx.isPermitSatisfied($0) }
            .compactMap { ctx.planFor(permit: $0)?.remainingSegmentCost }
            .reduce(0, +)

        let segmentRoom = remainingSegments - incompleteCost
        let failProbability: Double
        if segmentRoom >= 10 {
            failProbability = 0.15
        } else if segmentRoom >= 5 {
            failProbability = 0.3
        } else if segmentRoom >= 0 {
            failProbability = 0.55
        } else {
            failProbability = 0.85
        }

        // We draw 3 and keep the best 1–2; assume we pick well.
        let expectedKept = avgPermit * 1.2
        let failureCost = avgPermit * failProbability * 2.0 // 2p swing on failure
        let turnCost = averagePointsPerTurn(ctx: ctx)

        let rawValue = expectedKept - failureCost - turnCost

        // Bonus if our current tickets are all done — new ones provide fresh goals.
        let allComplete = ctx.hand.permits.allSatisfy(ctx.isPermitSatisfied(_:))
        return rawValue + (allComplete ? 4.0 : 0.0)
    }

    private func averagePointsPerTurn(ctx: DecisionContext) -> Double {
        // Rough: length-3 route average + a little permit progress.
        let handCards = ctx.hand.cards.count
        if handCards < 3 { return 1.5 }
        return 3.0
    }

    // MARK: - Lookahead Re-Ranking

    private func rerankWithRollouts(candidates: [ScoredAction], round: Round, playerID: PlayerID) -> AIAction {
        let claimCandidates = candidates.prefix(lookaheadCandidateCount).filter {
            if case .claimRoute = $0.action { return true }
            return false
        }
        if claimCandidates.isEmpty { return candidates.first!.action }

        // For each top claim, simulate; pick max estimated final margin + heuristic.
        let baseSeed = UInt64(abs(round.id.hashValue &+ playerID.hashValue &+ round.log.count))
        var bestAction: AIAction = candidates.first!.action
        var bestScore: Double = -.infinity

        for candidate in candidates.prefix(lookaheadCandidateCount) {
            let margin = evaluateAction(candidate.action, from: round, playerID: playerID, baseSeed: baseSeed)
            let combined = candidate.score * 0.6 + margin * 0.4
            if combined > bestScore {
                bestScore = combined
                bestAction = candidate.action
            }
        }

        // Also always consider the heuristic top pick — lookahead is a re-ranker, not a gatekeeper.
        if candidates.first!.score * 0.6 + evaluateAction(candidates.first!.action, from: round, playerID: playerID, baseSeed: baseSeed) * 0.4 > bestScore {
            bestAction = candidates.first!.action
        }

        return bestAction
    }

    /// Runs a few short rollouts from `round` after applying `action` and returns the average score margin for `playerID`.
    private func evaluateAction(_ action: AIAction, from round: Round, playerID: PlayerID, baseSeed: UInt64) -> Double {
        var totalMargin: Double = 0
        var rollouts: Int = 0
        // Cheap rollout policy: the legacy greedy AI. Rollouts are for *relative* signal —
        // a fast, unbiased policy gives us far more samples per millisecond than running the
        // full utility policy recursively, and avoids the exponential blowup of nested lookahead.
        let rolloutPolicy = AIEngineExtreme(difficulty: .easy, visibility: .publicOnly, rolloutsPerCandidate: 0, lookaheadCandidateCount: 0)

        for i in 0..<max(1, rolloutsPerCandidate) {
            var sim = round
            do {
                try action.apply(to: &sim, playerID: playerID)
            } catch {
                return -.infinity
            }

            var rng = SplitMix64(seed: baseSeed &+ UInt64(i))
            playout(round: &sim, policy: rolloutPolicy, rng: &rng, maxPlies: 12)
            totalMargin += scoreMargin(round: sim, playerID: playerID)
            rollouts += 1
        }

        return rollouts > 0 ? totalMargin / Double(rollouts) : 0
    }

    /// Advances the simulated round using the rollout policy until the game ends or the ply budget is exhausted.
    private func playout(round: inout Round, policy: AIEngineExtreme, rng: inout SplitMix64, maxPlies: Int) {
        var plies = 0
        while !round.isComplete, plies < maxPlies {
            guard case .waitingForPlayer(let id, let phase) = round.state else { break }
            do {
                switch phase {
                case .choosingAction:
                    let action = policy.chooseAction(for: round, playerID: id)
                    try action.apply(to: &round, playerID: id)
                case .drawingSecondCard:
                    let action = policy.chooseAction(for: round, playerID: id)
                    try action.apply(to: &round, playerID: id)
                case .choosingPermits:
                    let action = policy.chooseAction(for: round, playerID: id)
                    try action.apply(to: &round, playerID: id)
                }
            } catch {
                break
            }
            plies += 1
            _ = rng.next() // reserved for future stochastic policies
        }
    }

    private func scoreMargin(round: Round, playerID: PlayerID) -> Double {
        // Project forward: include current score + estimated permit swing + longest-path estimate.
        var scores: [PlayerID: Double] = [:]
        for hand in round.playerHands {
            var s = Double(hand.player.score)
            for permit in hand.permits {
                if round.isPermitCompleted(permit: permit, playerID: hand.player.id) {
                    s += Double(permit.points)
                } else {
                    s -= Double(permit.points)
                }
            }
            scores[hand.player.id] = s
        }
        let longestOwners = round.playersWithLongestPath()
        for owner in longestOwners {
            scores[owner, default: 0] += 10.0
        }

        let me = scores[playerID] ?? 0
        let best = scores.filter { $0.key != playerID }.values.max() ?? 0
        return me - best
    }

    // MARK: - Permit Choice

    private func scoreInitialPermitSubset(
        indices: [Int],
        permits: [Permit],
        round: Round,
        playerID: PlayerID
    ) -> Double {
        let chosen = indices.map { permits[$0] }
        var score: Double = 0
        var citiesTouched: Set<City> = []

        for permit in chosen {
            let cost = shortestHandAwarePath(
                from: permit.city1,
                to: permit.city2,
                round: round,
                playerID: playerID,
                hand: nil
            )?.remainingSegmentCost
            if let cost, cost > 0 {
                score += Double(permit.points) / max(1.0, Double(cost)) * 10
            } else if cost == nil {
                score -= 20
            }
            citiesTouched.insert(permit.city1)
            citiesTouched.insert(permit.city2)
        }

        // Synergy: reward overlap in cities.
        let possibleCities = chosen.count * 2
        let saved = possibleCities - citiesTouched.count
        if saved > 0 {
            score += Double(saved) * 6
        }

        // Penalize pairs whose shortest paths are wildly different (hard to unify).
        if chosen.count >= 2 {
            let costs = chosen.compactMap { shortestHandAwarePath(from: $0.city1, to: $0.city2, round: round, playerID: playerID, hand: nil)?.remainingSegmentCost }
            if let maxCost = costs.max(), let minCost = costs.min(), maxCost - minCost > 10 {
                score -= 5
            }
        }

        // Light preference for keeping two rather than all three initially (keeping all three is a lot of segments to commit).
        if chosen.count == Round.minInitialPermitsToKeep {
            score += 3
        }

        return score
    }

    private func choosePermitsToKeep(drawn: [Permit], round: Round, playerID: PlayerID) -> [PermitID] {
        guard let hand = round.playerHand(for: playerID) else {
            return [drawn[0].id]
        }

        let myRoutes = round.claimedRoutes(for: playerID)
        let adj = buildAdjacency(from: myRoutes)
        let networkCities = Set(myRoutes.flatMap { [$0.city1, $0.city2] })
        let existingPermitCities = Set(hand.permits.flatMap { [$0.city1, $0.city2] })
        let relevantCities = networkCities.union(existingPermitCities)

        struct Scored { let permit: Permit; let score: Double }
        let scored: [Scored] = drawn.map { permit in
            var score: Double = 0
            if isConnected(from: permit.city1, to: permit.city2, adjacency: adj) {
                score += Double(permit.points) * 3
            }
            if relevantCities.contains(permit.city1) { score += 6 }
            if relevantCities.contains(permit.city2) { score += 6 }

            if let plan = shortestHandAwarePath(from: permit.city1, to: permit.city2, round: round, playerID: playerID, hand: hand) {
                let cost = max(1, plan.remainingSegmentCost)
                score += Double(permit.points) / Double(cost) * 5
            } else {
                score -= Double(permit.points) * 2.5
            }

            return Scored(permit: permit, score: score)
        }.sorted { $0.score > $1.score }

        // Always keep the top pick. Keep the second if it's close to the first (relative cutoff) or
        // shares a city with the first (synergy), and we have segments to spare.
        var kept: [PermitID] = [scored[0].permit.id]
        let segmentRoom = hand.remainingSegments

        if scored.count >= 2 {
            let first = scored[0].permit
            let second = scored[1].permit
            let relativeClose = scored[1].score >= scored[0].score * 0.6 && scored[1].score > 0
            let sharesCity = first.city1 == second.city1 || first.city1 == second.city2 ||
                             first.city2 == second.city1 || first.city2 == second.city2
            if segmentRoom > 12, (relativeClose || sharesCity) {
                kept.append(second.id)
            }
        }

        if scored.count >= 3 {
            let third = scored[2].permit
            let first = scored[0].permit
            let sharesCity = first.city1 == third.city1 || first.city1 == third.city2 ||
                             first.city2 == third.city1 || first.city2 == third.city2
            if segmentRoom > 20, sharesCity, scored[2].score > 0, scored[2].score >= scored[0].score * 0.6 {
                kept.append(third.id)
            }
        }

        return kept
    }

    // MARK: - Card Drawing

    private enum DrawPhase { case first, second }

    /// Shared ranker for face-up and deck draws. In the second phase we cannot pick wilds.
    private func bestDrawCardAction(
        round: Round,
        playerID: PlayerID,
        desiredColors: [CardColor: Double],
        phase: DrawPhase
    ) -> AIAction {
        guard round.canDrawAnyCard else { return .drawCards(source: .drawPile) }

        // Wild-snipe logic only on the first draw.
        if phase == .first {
            let usefulFaceUps = round.faceUpCards.compactMap { round.cardsMap[$0] }.filter { card in
                !card.isWild && (desiredColors[card.color] ?? 0) > 0
            }.count
            if usefulFaceUps < 2 {
                if let idx = round.faceUpCards.firstIndex(where: { round.cardsMap[$0]?.isWild == true }) {
                    return .drawCards(source: .faceUp(index: idx))
                }
            }
        }

        // Score each face-up option by desired-color weight; forbid wilds on second draw.
        var bestIndex: Int?
        var bestScore: Double = 0
        for (index, cardID) in round.faceUpCards.enumerated() {
            guard let card = round.cardsMap[cardID] else { continue }
            if card.isWild {
                if phase == .second { continue }
                // Handled by wild-snipe above; skip here so we don't double-count.
                continue
            }
            let score = (desiredColors[card.color] ?? 0) + 0.1 // tiny prior so we still accept face-ups when no desire map exists
            if score > bestScore {
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

        // Last resort: take any face-up that's legal for this phase.
        for (index, cardID) in round.faceUpCards.enumerated() {
            let isWild = round.cardsMap[cardID]?.isWild == true
            if phase == .second, isWild { continue }
            return .drawCards(source: .faceUp(index: index))
        }

        return .drawCards(source: .drawPile)
    }

    private func chooseSecondCardDraw(round: Round, playerID: PlayerID) -> AIAction {
        guard let hand = round.playerHand(for: playerID) else {
            return bestDrawCardAction(round: round, playerID: playerID, desiredColors: [:], phase: .second)
        }
        let ctx = DecisionContext(round: round, playerID: playerID, hand: hand, engine: self)
        return bestDrawCardAction(round: round, playerID: playerID, desiredColors: ctx.desiredColors, phase: .second)
    }

    // MARK: - Legacy (Easy) Policy

    /// Original greedy AI kept verbatim as the easy difficulty for regression / tutorial.
    private func legacyChooseMainAction(round: Round, playerID: PlayerID) -> AIAction {
        guard let hand = round.playerHand(for: playerID) else {
            return bestDrawCardAction(round: round, playerID: playerID, desiredColors: [:], phase: .first)
        }

        let ctx = DecisionContext(round: round, playerID: playerID, hand: hand, engine: self)
        let claimable = round.claimableRoutes(for: playerID)
        let scored = claimable.map { entry -> (Route, [CardID], Double) in
            var score = Double(Route.routeScore(length: entry.route.length))
            for permit in hand.permits {
                if isConnected(from: permit.city1, to: permit.city2, adjacency: ctx.myAdjacency) { continue }
                if wouldCompletePermit(route: entry.route, permit: permit, myRoutes: ctx.myRoutes) {
                    score += Double(permit.points) * 5
                }
            }
            if ctx.anyPlanContains(routeID: entry.route.id) { score += 4 }
            return (entry.route, entry.cardIDs, score)
        }
        let best = scored.max(by: { $0.2 < $1.2 })

        if let best, best.2 >= 10 {
            return .claimRoute(routeID: best.0.id, cardIDs: best.1)
        }
        if round.isFinalRound, let best, best.2 > 0 {
            return .claimRoute(routeID: best.0.id, cardIDs: best.1)
        }
        if let best, best.2 >= 3, hand.cards.count >= 4 {
            return .claimRoute(routeID: best.0.id, cardIDs: best.1)
        }
        if round.canDrawAnyCard {
            return bestDrawCardAction(round: round, playerID: playerID, desiredColors: ctx.desiredColors, phase: .first)
        }
        if !round.permitDeck.isEmpty {
            return .drawPermits
        }
        return .drawCards(source: .drawPile)
    }

    // MARK: - Path Planning

    struct Plan {
        /// Unclaimed route IDs the player needs to claim (in no particular order).
        let edgeIDs: Set<RouteID>
        /// Sum of route lengths over `edgeIDs`.
        let remainingSegmentCost: Int
    }

    /// Dijkstra over the unclaimed subgraph, with the edge cost augmented by color feasibility given
    /// the current hand (wild cards count as slack). Already-claimed routes by the player are free edges.
    func shortestHandAwarePath(
        from start: City,
        to end: City,
        round: Round,
        playerID: PlayerID,
        hand: PlayerHand?
    ) -> Plan? {
        struct Edge {
            let routeID: RouteID
            let destination: City
            let cost: Int
            let needsToClaim: Bool
        }

        let handCards: [Card]? = hand.map { $0.cards.compactMap { round.cardsMap[$0] } }

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

            let deficitPenalty: Int
            if let handCards {
                deficitPenalty = colorDeficit(route: route, handCards: handCards) * 2
            } else {
                deficitPenalty = 0
            }
            let cost = route.length + deficitPenalty
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

        var edgeIDs: Set<RouteID> = []
        var city = end
        while city != start {
            guard let step = prev[city] else { return nil }
            if step.needsToClaim { edgeIDs.insert(step.routeID) }
            city = step.city
        }

        let totalLength = edgeIDs.reduce(0) { sum, id in
            sum + (round.routes.first(where: { $0.id == id })?.length ?? 0)
        }
        return Plan(edgeIDs: edgeIDs, remainingSegmentCost: totalLength)
    }

    // MARK: - Color Feasibility

    /// How many cards (beyond what we already hold) we'd need in order to claim `route`.
    /// Wilds count against any color. Returns 0 if already claimable.
    private func colorDeficit(route: Route, handCards: [Card]) -> Int {
        let wilds = handCards.filter(\.isWild).count
        let nonWild = handCards.filter { !$0.isWild }

        switch route.color {
        case .any:
            let bestCount = Dictionary(grouping: nonWild, by: \.color).mapValues(\.count).values.max() ?? 0
            let usable = bestCount + wilds
            return max(0, route.length - usable)
        default:
            guard let required = route.color.cardColor else { return 0 }
            let matching = nonWild.filter { $0.color == required }.count
            let usable = matching + wilds
            return max(0, route.length - usable)
        }
    }

    private func cardCountsByColor(handCards: [Card]) -> [CardColor: Int] {
        var counts: [CardColor: Int] = [:]
        for card in handCards {
            counts[card.color, default: 0] += 1
        }
        return counts
    }

    // MARK: - Graph Utilities

    func buildAdjacency(from routes: [Route]) -> [City: Set<City>] {
        var adj: [City: Set<City>] = [:]
        for route in routes {
            adj[route.city1, default: []].insert(route.city2)
            adj[route.city2, default: []].insert(route.city1)
        }
        return adj
    }

    func isConnected(from city1: City, to city2: City, adjacency: [City: Set<City>]) -> Bool {
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

    func wouldCompletePermit(route: Route, permit: Permit, myRoutes: [Route]) -> Bool {
        var adj = buildAdjacency(from: myRoutes)
        adj[route.city1, default: []].insert(route.city2)
        adj[route.city2, default: []].insert(route.city1)
        return isConnected(from: permit.city1, to: permit.city2, adjacency: adj)
    }

    /// Pure version of `Round.longestContinuousPath(for:)` — operates on a plain list of routes.
    /// Iterative DFS (each route used at most once) over the graph.
    func longestContinuousPathLength(routes: [Route]) -> Int {
        if routes.isEmpty { return 0 }

        var adjacency: [City: [(city: City, routeID: RouteID, length: Int)]] = [:]
        for route in routes {
            adjacency[route.city1, default: []].append((city: route.city2, routeID: route.id, length: route.length))
            adjacency[route.city2, default: []].append((city: route.city1, routeID: route.id, length: route.length))
        }

        var maxLength = 0
        let cities = Set(routes.flatMap { [$0.city1, $0.city2] })
        for city in cities {
            var used: Set<RouteID> = []
            dfsLongest(from: city, adjacency: adjacency, used: &used, currentLength: 0, maxLength: &maxLength)
        }
        return maxLength
    }

    private func dfsLongest(
        from city: City,
        adjacency: [City: [(city: City, routeID: RouteID, length: Int)]],
        used: inout Set<RouteID>,
        currentLength: Int,
        maxLength: inout Int
    ) {
        if currentLength > maxLength { maxLength = currentLength }
        for edge in adjacency[city] ?? [] where !used.contains(edge.routeID) {
            used.insert(edge.routeID)
            dfsLongest(from: edge.city, adjacency: adjacency, used: &used, currentLength: currentLength + edge.length, maxLength: &maxLength)
            used.remove(edge.routeID)
        }
    }

    // MARK: - Misc

    private func allSubsets(count: Int, minSize: Int) -> [[Int]] {
        var result: [[Int]] = []
        let total = 1 << count
        for mask in 0..<total {
            var indices: [Int] = []
            for i in 0..<count where (mask >> i) & 1 == 1 {
                indices.append(i)
            }
            if indices.count >= minSize { result.append(indices) }
        }
        return result
    }
}

// MARK: - Decision Context

/// Bundle of precomputed values used by the utility policy. Recomputing these per candidate is cheap
/// relative to the number of claimable routes, but the bundle keeps the math readable.
private struct DecisionContext {
    let round: Round
    let playerID: PlayerID
    let hand: PlayerHand
    let engine: AIEngineExtreme

    let myRoutes: [Route]
    let myAdjacency: [City: Set<City>]
    let myNetworkCities: Set<City>
    let desiredColors: [CardColor: Double]

    /// Per-route blocking value built from opponent permits (hard difficulty only).
    /// Precomputed so per-candidate scoring is a single dictionary lookup.
    let blockingValuePerRoute: [RouteID: Double]

    /// Cached plan per outstanding permit. `nil` means no feasible path found.
    private let plans: [PermitID: AIEngineExtreme.Plan?]
    /// Routes that appear in at least one plan, for fast membership tests.
    private let planEdges: Set<RouteID>

    init(round: Round, playerID: PlayerID, hand: PlayerHand, engine: AIEngineExtreme) {
        self.round = round
        self.playerID = playerID
        self.hand = hand
        self.engine = engine

        let mine = round.claimedRoutes(for: playerID)
        self.myRoutes = mine
        let adj = engine.buildAdjacency(from: mine)
        self.myAdjacency = adj
        self.myNetworkCities = Set(mine.flatMap { [$0.city1, $0.city2] })

        var plans: [PermitID: AIEngineExtreme.Plan?] = [:]
        var edges: Set<RouteID> = []
        var colorWeights: [CardColor: Double] = [:]

        for permit in hand.permits {
            if engine.isConnected(from: permit.city1, to: permit.city2, adjacency: adj) {
                plans[permit.id] = .some(AIEngineExtreme.Plan(edgeIDs: [], remainingSegmentCost: 0))
                continue
            }
            if let plan = engine.shortestHandAwarePath(from: permit.city1, to: permit.city2, round: round, playerID: playerID, hand: hand) {
                plans[permit.id] = .some(plan)
                for id in plan.edgeIDs {
                    edges.insert(id)
                    if let route = round.routes.first(where: { $0.id == id }) {
                        switch route.color {
                        case .any:
                            for c in CardColor.regularColors {
                                colorWeights[c, default: 0] += Double(permit.points) * 0.3
                            }
                        default:
                            if let cc = route.color.cardColor {
                                colorWeights[cc, default: 0] += Double(permit.points)
                            }
                        }
                    }
                }
            } else {
                plans[permit.id] = .none
            }
        }

        self.plans = plans
        self.planEdges = edges
        self.desiredColors = colorWeights

        // Precompute opponent-permit blocking value per route.
        var blockTable: [RouteID: Double] = [:]
        if engine.visibility.canSeeOpponentPermits {
            for oppHand in round.playerHands where oppHand.player.id != playerID {
                let oppRoutes = round.claimedRoutes(for: oppHand.player.id)
                let oppAdj = engine.buildAdjacency(from: oppRoutes)
                for permit in oppHand.permits {
                    if engine.isConnected(from: permit.city1, to: permit.city2, adjacency: oppAdj) { continue }
                    let oppHandArg: PlayerHand? = engine.visibility.canSeeOpponentHands ? oppHand : nil
                    guard let plan = engine.shortestHandAwarePath(
                        from: permit.city1,
                        to: permit.city2,
                        round: round,
                        playerID: oppHand.player.id,
                        hand: oppHandArg
                    ) else { continue }
                    let urgency: Double
                    if plan.remainingSegmentCost <= 4 {
                        urgency = 3.0
                    } else if plan.remainingSegmentCost <= 7 {
                        urgency = 1.5
                    } else {
                        urgency = 0.6
                    }
                    let addend = Double(permit.points) * urgency
                    for id in plan.edgeIDs {
                        blockTable[id, default: 0] += addend
                    }
                }
            }
        }
        self.blockingValuePerRoute = blockTable
    }

    func planFor(permit: Permit) -> AIEngineExtreme.Plan? {
        guard let entry = plans[permit.id] else { return nil }
        return entry
    }

    func anyPlanContains(routeID: RouteID) -> Bool {
        planEdges.contains(routeID)
    }

    func isPermitSatisfied(_ permit: Permit) -> Bool {
        engine.isConnected(from: permit.city1, to: permit.city2, adjacency: myAdjacency)
    }
}

private struct ScoredAction {
    let action: AIAction
    let score: Double
}

// MARK: - Deterministic RNG

/// SplitMix64 gives a reproducible stream for seeded playouts without hitting the global RNG.
/// Rollout budgets are small, so this is plenty even for thousands of calls.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
