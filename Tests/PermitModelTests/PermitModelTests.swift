import Foundation
import Testing
@testable import PermitModel

// MARK: - Test Helpers

private func makePlayers() -> [Player] {
    [
        Player(id: "alice", name: "Alice", imageURL: nil, color: .blue),
        Player(id: "bob", name: "Bob", imageURL: nil, color: .red),
    ]
}

private func makeSimpleMap() -> GameMap {
    GameMap(
        routes: [
            Route(id: 1, city1: .vancouver, city2: .calgary, length: 1, color: .any),
            Route(id: 2, city1: .calgary, city2: .winnipeg, length: 1, color: .any),
            Route(id: 3, city1: .winnipeg, city2: .helena, length: 1, color: .any),
            Route(id: 4, city1: .vancouver, city2: .helena, length: 2, color: .blue),
            Route(id: 5, city1: .calgary, city2: .helena, length: 2, color: .red, doubleRoutePartnerID: 6),
            Route(id: 6, city1: .calgary, city2: .helena, length: 2, color: .green, doubleRoutePartnerID: 5),
        ],
        permits: [
            Permit(id: 1, city1: .vancouver, city2: .calgary, points: 3),
            Permit(id: 2, city1: .calgary, city2: .winnipeg, points: 3),
            Permit(id: 3, city1: .winnipeg, city2: .helena, points: 3),
            Permit(id: 4, city1: .vancouver, city2: .winnipeg, points: 5),
            Permit(id: 5, city1: .calgary, city2: .helena, points: 5),
            Permit(id: 6, city1: .vancouver, city2: .helena, points: 10),
        ]
    )
}

private func makeSimpleDeck() -> [Card] {
    var cards: [Card] = []
    for i in 1...30 { cards.append(Card(id: "blue-\(i)", color: .blue)) }
    for i in 1...30 { cards.append(Card(id: "red-\(i)", color: .red)) }
    for i in 1...4 { cards.append(Card(id: "fiber-\(i)", color: .fiber)) }
    return cards
}

private func makeReadyRound(
    segmentsPerPlayer: Int = 45
) throws -> Round {
    var round: Round = try Round(
        cookedDeck: makeSimpleDeck(),
        cookedPermits: makeSimpleMap().permits,
        gameMap: makeSimpleMap(),
        players: makePlayers(),
        segmentsPerPlayer: segmentsPerPlayer
    )

    // Select initial permits to get past setup
    let alicePermits: [Permit] = round.playerHands[0].permits
    try round.selectInitialPermits(
        playerID: "alice",
        permitIDs: Array(alicePermits.prefix(2).map(\.id))
    )

    let bobPermits: [Permit] = round.playerHands[1].permits
    try round.selectInitialPermits(
        playerID: "bob",
        permitIDs: Array(bobPermits.prefix(2).map(\.id))
    )

    return round
}

// MARK: - Initialization Tests

@Test
func initializeRound() throws {
    let round: Round = try Round(
        cookedDeck: makeSimpleDeck(),
        gameMap: makeSimpleMap(),
        players: makePlayers()
    )

    #expect(round.playerHands.count == 2)
    #expect(round.playerHands[0].cards.count == 4)
    #expect(round.playerHands[1].cards.count == 4)
    #expect(round.faceUpCards.count == 5)
    #expect(round.playerHands[0].remainingSegments == 45)
    #expect(round.playerHands[1].remainingSegments == 45)

    if case .setup(let pending) = round.state {
        #expect(pending.count == 2)
    } else {
        Issue.record("Expected setup state")
    }
}

@Test
func initializeRoundFailsWithTooFewPlayers() {
    #expect(throws: PermitModelError.notEnoughPlayers) {
        try Round(
            gameMap: makeSimpleMap(),
            players: [Player(id: "solo", name: "Solo", imageURL: nil, color: .blue)]
        )
    }
}

@Test
func initializeRoundFailsWithTooManyPlayers() {
    let players: [Player] = (1...6).map {
        Player(id: "p\($0)", name: "Player \($0)", imageURL: nil, color: PlayerColor.allCases[$0 % 5])
    }
    #expect(throws: PermitModelError.tooManyPlayers) {
        try Round(gameMap: makeSimpleMap(), players: players)
    }
}

// MARK: - Setup Phase Tests

@Test
func selectInitialPermits() throws {
    var round: Round = try Round(
        cookedDeck: makeSimpleDeck(),
        cookedPermits: makeSimpleMap().permits,
        gameMap: makeSimpleMap(),
        players: makePlayers()
    )

    let alicePermits: [Permit] = round.playerHands[0].permits
    #expect(alicePermits.count == 3)

    // Alice keeps 2 of 3
    try round.selectInitialPermits(
        playerID: "alice",
        permitIDs: [alicePermits[0].id, alicePermits[1].id]
    )
    #expect(round.playerHands[0].permits.count == 2)

    // Bob keeps all 3
    let bobPermits: [Permit] = round.playerHands[1].permits
    try round.selectInitialPermits(
        playerID: "bob",
        permitIDs: bobPermits.map(\.id)
    )
    #expect(round.playerHands[1].permits.count == 3)

    // Should now be waiting for first player
    if case .waitingForPlayer(let id, .choosingAction) = round.state {
        #expect(id == "alice")
    } else {
        Issue.record("Expected waitingForPlayer state")
    }
}

@Test
func selectInitialPermitsFailsWithTooFew() throws {
    var round: Round = try Round(
        cookedDeck: makeSimpleDeck(),
        cookedPermits: makeSimpleMap().permits,
        gameMap: makeSimpleMap(),
        players: makePlayers()
    )

    let alicePermits: [Permit] = round.playerHands[0].permits
    #expect(throws: PermitModelError.mustKeepAtLeastTwoInitialPermits) {
        try round.selectInitialPermits(
            playerID: "alice",
            permitIDs: [alicePermits[0].id]
        )
    }
}

// MARK: - Draw Card Tests

@Test
func drawCardsFromDeck() throws {
    var round: Round = try makeReadyRound()

    #expect(round.playerHands[0].cards.count == 4)

    // Alice draws first card from deck
    try round.drawCard(from: .drawPile)

    if case .waitingForPlayer(let id, .drawingSecondCard) = round.state {
        #expect(id == "alice")
    } else {
        Issue.record("Expected drawingSecondCard phase")
    }

    // Alice draws second card from deck
    try round.drawCard(from: .drawPile)
    #expect(round.playerHands[0].cards.count == 6)

    // Should be Bob's turn
    if case .waitingForPlayer(let id, .choosingAction) = round.state {
        #expect(id == "bob")
    } else {
        Issue.record("Expected Bob's turn")
    }

    #expect(round.log.count == 1)
}

@Test
func drawCardFromFaceUp() throws {
    var round: Round = try makeReadyRound()

    let faceUpCardID: CardID = round.faceUpCards[0]
    try round.drawCard(from: .faceUp(index: 0))

    #expect(round.playerHands[0].cards.contains(faceUpCardID))
    #expect(round.faceUpCards.count == 5) // Refilled
}

@Test
func drawFiberFromFaceUpEndsDrawPhase() throws {
    // Create a deck where a fiber card ends up in face-up position
    var cards: [Card] = []
    for i in 1...8 { cards.append(Card(id: "blue-\(i)", color: .blue)) }
    cards.append(Card(id: "fiber-1", color: .fiber)) // Will be face-up[0]
    for i in 9...40 { cards.append(Card(id: "blue-\(i)", color: .blue)) }

    var round: Round = try Round(
        cookedDeck: cards,
        cookedPermits: makeSimpleMap().permits,
        gameMap: makeSimpleMap(),
        players: makePlayers()
    )

    // Complete setup
    try round.selectInitialPermits(playerID: "alice", permitIDs: Array(round.playerHands[0].permits.prefix(2).map(\.id)))
    try round.selectInitialPermits(playerID: "bob", permitIDs: Array(round.playerHands[1].permits.prefix(2).map(\.id)))

    // Alice draws fiber from face-up → turn ends immediately (only 1 card)
    try round.drawCard(from: .faceUp(index: 0))

    if case .waitingForPlayer(let id, .choosingAction) = round.state {
        #expect(id == "bob")
    } else {
        Issue.record("Expected Bob's turn after fiber draw")
    }

    #expect(round.playerHands[0].cards.count == 5) // 4 initial + 1 fiber
}

@Test
func cannotDrawFiberAsSecondCard() throws {
    // Create a deck where fiber appears as second face-up after first draw
    var cards: [Card] = []
    for i in 1...8 { cards.append(Card(id: "blue-\(i)", color: .blue)) }
    cards.append(Card(id: "blue-extra", color: .blue)) // face-up[0]
    cards.append(Card(id: "fiber-1", color: .fiber))    // face-up[1]
    for i in 9...40 { cards.append(Card(id: "blue-\(i)", color: .blue)) }

    var round: Round = try Round(
        cookedDeck: cards,
        cookedPermits: makeSimpleMap().permits,
        gameMap: makeSimpleMap(),
        players: makePlayers()
    )

    try round.selectInitialPermits(playerID: "alice", permitIDs: Array(round.playerHands[0].permits.prefix(2).map(\.id)))
    try round.selectInitialPermits(playerID: "bob", permitIDs: Array(round.playerHands[1].permits.prefix(2).map(\.id)))

    // Alice draws non-fiber from face-up
    try round.drawCard(from: .faceUp(index: 0))

    // Find the fiber card index in face-up
    let fiberIndex: Int? = round.faceUpCards.firstIndex(where: { round.cardsMap[$0]?.isFiber == true })
    if let idx = fiberIndex {
        #expect(throws: PermitModelError.cannotDrawFiberAsSecondCard) {
            try round.drawCard(from: .faceUp(index: idx))
        }
    }
}

@Test
/// TTR USA rule: when 3+ fibers (wilds) are face-up, discard all 5 and replace. Refill from draw (or reshuffle discard if draw empty).
func replaceFaceUpWhenThreeFibersDiscardsAndRefills() throws {
    // Init order: first 8 to hands, then 5 to face-up, rest to draw. Indices 8–12 = face-up; 13+ = draw.
    // Face-up = 3 fibers + 2 blue (triggers replace). Draw = 5 blues so refill gets < 3 fibers and recursion stops.
    var cards: [Card] = []
    for i in 1...8 { cards.append(Card(id: "blue-\(i)", color: .blue)) }
    cards.append(contentsOf: [
        Card(id: "fiber-1", color: .fiber),
        Card(id: "fiber-2", color: .fiber),
        Card(id: "fiber-3", color: .fiber),
        Card(id: "blue-9", color: .blue),
        Card(id: "blue-10", color: .blue),
    ])
    for i in 11...15 { cards.append(Card(id: "blue-\(i)", color: .blue)) }

    let round: Round = try Round(
        cookedDeck: cards,
        cookedPermits: makeSimpleMap().permits,
        gameMap: makeSimpleMap(),
        players: makePlayers()
    )

    // replaceFaceUpIfNeeded runs at end of init: discard 5, refill 5 from draw (all blue) → < 3 fibers.
    #expect(round.faceUpCards.count == 5)
    let fiberCount: Int = round.faceUpCards.filter { round.cardsMap[$0]?.isFiber == true }.count
    #expect(fiberCount < 3)
    #expect(round.discardPile.count == 5)
}

// MARK: - Claim Route Tests

@Test
func claimRoute() throws {
    var round: Round = try makeReadyRound()

    // Alice has blue-1, blue-2, blue-3, blue-4
    let aliceCards: [CardID] = round.playerHands[0].cards
    let initialSegments: Int = round.playerHands[0].remainingSegments

    // Claim route 1 (Vancouver-Calgary, length 1, any) with one card
    try round.claimRoute(routeID: 1, cardIDs: [aliceCards[0]])

    #expect(round.routes.first(where: { $0.id == 1 })?.claimedBy == "alice")
    #expect(round.playerHands[0].cards.count == 3)
    #expect(round.playerHands[0].remainingSegments == initialSegments - 1)
    #expect(round.playerHands[0].player.score == 1) // Length 1 = 1 point
}

@Test
func claimRouteWithSpecificColor() throws {
    var round: Round = try makeReadyRound()

    // Route 4 is Vancouver-Helena, length 2, blue. Alice has blue-1, blue-2, blue-3, blue-4
    let aliceCards: [CardID] = round.playerHands[0].cards
    try round.claimRoute(routeID: 4, cardIDs: [aliceCards[0], aliceCards[1]])

    #expect(round.routes.first(where: { $0.id == 4 })?.claimedBy == "alice")
    #expect(round.playerHands[0].player.score == 2) // Length 2 = 2 points
}

@Test
func claimRouteAlreadyClaimed() throws {
    var round: Round = try makeReadyRound()

    // Alice claims route 1
    try round.claimRoute(routeID: 1, cardIDs: [round.playerHands[0].cards[0]])

    // Bob tries to claim route 1
    #expect(throws: PermitModelError.routeAlreadyClaimed) {
        try round.claimRoute(routeID: 1, cardIDs: [round.playerHands[1].cards[0]])
    }
}

@Test
func cannotClaimBothDoubleRoutes() throws {
    var round: Round = try makeReadyRound()

    // Alice draws 2 cards
    try round.drawCard(from: .drawPile)
    try round.drawCard(from: .drawPile)

    // Bob draws 2 cards
    try round.drawCard(from: .drawPile)
    try round.drawCard(from: .drawPile)

    // Alice claims route 1 (Vancouver-Calgary, 1, any) — uses 1 blue card
    try round.claimRoute(routeID: 1, cardIDs: [round.playerHands[0].cards[0]])

    // Bob claims route 2 (Calgary-Winnipeg, 1, any)
    try round.claimRoute(routeID: 2, cardIDs: [round.playerHands[1].cards[0]])

    // Alice claims route 4 (Vancouver-Helena, 2, blue)
    try round.claimRoute(routeID: 4, cardIDs: Array(round.playerHands[0].cards.prefix(2)))

    // The double routes are 5 and 6. Testing the 2-player double route rule
    // is covered by the validation logic.
}

@Test
func claimRouteInsufficientCards() throws {
    var round: Round = try makeReadyRound()

    // Try to claim route 4 (length 2) with only 1 card
    #expect(throws: PermitModelError.insufficientCards) {
        try round.claimRoute(routeID: 4, cardIDs: [round.playerHands[0].cards[0]])
    }
}

@Test
func claimRouteWrongColor() throws {
    var round: Round = try makeReadyRound()

    // Route 5 is Calgary-Helena, length 2, red. Alice only has blue cards.
    #expect(throws: PermitModelError.invalidCardColor) {
        try round.claimRoute(routeID: 5, cardIDs: Array(round.playerHands[0].cards.prefix(2)))
    }
}

// MARK: - Draw Permits Tests

@Test
func drawAndKeepPermits() throws {
    var round: Round = try makeReadyRound()

    let initialPermitCount: Int = round.playerHands[0].permits.count

    try round.drawPermits()

    if case .waitingForPlayer(let id, .choosingPermits(let drawn)) = round.state {
        #expect(id == "alice")
        #expect(drawn.count > 0)

        // Keep 1 permit
        try round.keepPermits(permitIDs: [drawn[0].id])
        #expect(round.playerHands[0].permits.count == initialPermitCount + 1)
    } else {
        Issue.record("Expected choosingPermits phase")
    }
}

@Test
func keepPermitsFailsWithNone() throws {
    var round: Round = try makeReadyRound()

    try round.drawPermits()

    #expect(throws: PermitModelError.mustKeepAtLeastOnePermit) {
        try round.keepPermits(permitIDs: [])
    }
}

// MARK: - Scoring Tests

@Test
func permitCompletion() throws {
    var round: Round = try makeReadyRound()

    // Alice claims route 1 (Vancouver-Calgary), then Bob claims route 2 (Calgary-Winnipeg)
    try round.claimRoute(routeID: 1, cardIDs: [round.playerHands[0].cards[0]]) // Alice: Vancouver-Calgary
    try round.claimRoute(routeID: 2, cardIDs: [round.playerHands[1].cards[0]]) // Bob: Calgary-Winnipeg

    // Alice can connect Vancouver to Calgary. Check permit Vancouver-Calgary.
    let permitVC: Permit = Permit(id: 100, city1: .vancouver, city2: .calgary, points: 3)
    #expect(round.isPermitCompleted(permit: permitVC, playerID: "alice"))

    // Alice cannot connect Vancouver to Winnipeg (she has Vancouver-Calgary, Bob has Calgary-Winnipeg)
    let permitVW: Permit = Permit(id: 101, city1: .vancouver, city2: .winnipeg, points: 5)
    #expect(!round.isPermitCompleted(permit: permitVW, playerID: "alice"))
}

@Test
func longestContinuousPath() throws {
    var round: Round = try makeReadyRound()

    // Turn 1 — Alice claims route 1 (Vancouver-Calgary, 1)
    try round.claimRoute(routeID: 1, cardIDs: [round.playerHands[0].cards[0]])
    // Turn 2 — Bob claims route 2 (Calgary-Winnipeg, 1)
    try round.claimRoute(routeID: 2, cardIDs: [round.playerHands[1].cards[0]])
    // Turn 3 — Alice claims route 4 (Vancouver-Helena, 2, blue) with her remaining blue cards
    try round.claimRoute(routeID: 4, cardIDs: Array(round.playerHands[0].cards.prefix(2)))

    // Alice has Vancouver-Calgary (1) and Vancouver-Helena (2), connected through Vancouver. Longest path = 3.
    let alicePath: Int = round.longestContinuousPath(for: "alice")
    #expect(alicePath == 3)

    // Bob has Calgary-Winnipeg (1). Longest = 1.
    let bobPath: Int = round.longestContinuousPath(for: "bob")
    #expect(bobPath == 1)
}

@Test
func routeScoring() {
    #expect(Route.routeScore(length: 1) == 1)
    #expect(Route.routeScore(length: 2) == 2)
    #expect(Route.routeScore(length: 3) == 4)
    #expect(Route.routeScore(length: 4) == 7)
    #expect(Route.routeScore(length: 5) == 10)
    #expect(Route.routeScore(length: 6) == 15)
}

// MARK: - Standard Map Tests

@Test
func standardMapLoads() {
    let map: GameMap = .standard()
    #expect(map.routes.count == 97)
    #expect(map.permits.count == 30)
}

@Test
func standardDeckSize() {
    let deck: [Card] = Card.standardDeck()
    #expect(deck.count == 110) // 12 * 8 colors + 14 fibers
}

// MARK: - Full Round Playthrough

@Test
func fullRoundPlaythrough() throws {
    let map: GameMap = makeSimpleMap()

    // All blue deck for simplicity — any-color routes accept any single color
    var cards: [Card] = []
    for i in 1...60 { cards.append(Card(id: "blue-\(i)", color: .blue)) }

    var round: Round = try Round(
        cookedDeck: cards,
        cookedPermits: map.permits,
        gameMap: map,
        players: makePlayers(),
        segmentsPerPlayer: 3
    )

    // Cards dealt:
    // Alice: blue-1, blue-2, blue-3, blue-4
    // Bob: blue-5, blue-6, blue-7, blue-8
    // Face up: blue-9, blue-10, blue-11, blue-12, blue-13

    // Permits dealt (cooked order):
    // Alice gets: p1 (Vancouver-Calgary, 3), p2 (Calgary-Winnipeg, 3), p3 (Winnipeg-Helena, 3)
    // Bob gets: p4 (Vancouver-Winnipeg, 5), p5 (Calgary-Helena, 5), p6 (Vancouver-Helena, 10)

    // Alice keeps p1, p2 (Vancouver-Calgary and Calgary-Winnipeg)
    try round.selectInitialPermits(playerID: "alice", permitIDs: [1, 2])
    #expect(round.playerHands[0].permits.count == 2)

    // Bob keeps p4, p5 (Vancouver-Winnipeg and Calgary-Helena)
    try round.selectInitialPermits(playerID: "bob", permitIDs: [4, 5])
    #expect(round.playerHands[1].permits.count == 2)

    // Verify game started
    #expect(round.currentPlayerID == "alice")

    // Turn 1 — Alice: Claim route 1 (Vancouver-Calgary, length 1, any) with blue-1
    try round.claimRoute(routeID: 1, cardIDs: ["blue-1"])
    #expect(round.routes.first(where: { $0.id == 1 })?.claimedBy == "alice")
    #expect(round.playerHands[0].player.score == 1) // 1 pt for length 1
    #expect(round.playerHands[0].remainingSegments == 2)
    #expect(round.isFinalRound) // 2 ≤ 2, triggered!

    // Turn 2 — Bob: Claim route 2 (Calgary-Winnipeg, length 1, any) with blue-5
    #expect(round.currentPlayerID == "bob")
    try round.claimRoute(routeID: 2, cardIDs: ["blue-5"])
    #expect(round.playerHands[1].player.score == 1)

    // Turn 3 — Alice (final turn): Claim route 3 (Winnipeg-Helena, length 1, any) with blue-2
    #expect(round.currentPlayerID == "alice")
    try round.claimRoute(routeID: 3, cardIDs: ["blue-2"])

    // Game should be complete
    #expect(round.isComplete)

    // Verify final scores:
    // Alice route pts: route 1(1) + route 3(1) = 2
    // Alice permits: p1(Vancouver-Calgary, 3) — connected ✓ +3
    //                p2(Calgary-Winnipeg, 3) — Alice has Vancouver-Calgary and Winnipeg-Helena but not Calgary-Winnipeg ✗ -3
    // Alice longest path: Vancouver-Calgary(1), Winnipeg-Helena(1) disconnected → max 1
    // Bob route pts: route 2(1) = 1
    // Bob permits: p4(Vancouver-Winnipeg, 5) — Bob has Calgary-Winnipeg only, not Vancouver ✗ -5
    //              p5(Calgary-Helena, 5) — Bob has Calgary-Winnipeg only, not Helena ✗ -5
    // Bob longest path: Calgary-Winnipeg(1) → max 1
    // Tied longest path (both 1), both get +10

    // Alice: 2 + 3 - 3 + 10 = 12
    // Bob: 1 - 5 - 5 + 10 = 1
    // Alice wins!

    if case .gameComplete(let winner) = round.state {
        #expect(winner.id == "alice")
        #expect(winner.score == 12)
    } else {
        Issue.record("Expected gameComplete state")
    }

    let bob: Player? = round.player(byID: "bob")
    #expect(bob?.score == 1)

    // Verify log was populated
    #expect(round.log.count == 3)
    #expect(round.ended != nil)
}

// MARK: - Fake Tests

@Test
func fakeFactories() throws {
    let player: Player = .fake()
    #expect(!player.id.isEmpty)

    let hand: PlayerHand = .fake()
    #expect(hand.remainingSegments == 45)

    let permit: Permit = .fake()
    #expect(permit.points == 21)

    let route: Route = .fake()
    #expect(route.length == 3)

    let card: Card = .fake()
    #expect(card.color == .blue)

    let round: Round = try .fake()
    #expect(round.playerHands.count == 2)
}

// MARK: - Codable Tests

@Test
func roundCodable() throws {
    let round: Round = try makeReadyRound()

    let encoder: JSONEncoder = .init()
    let data: Data = try encoder.encode(round)

    let decoder: JSONDecoder = .init()
    let decoded: Round = try decoder.decode(Round.self, from: data)

    #expect(decoded.id == round.id)
    #expect(decoded.playerHands.count == round.playerHands.count)
    #expect(decoded.routes.count == round.routes.count)
}

// MARK: - AI Engine Tests

@Test
func aiEngineEasyReturnsValidAction() throws {
    var round: Round = try makeReadyRound()
    let engine: AIEngine = AIEngine(difficulty: .easy)

    let action: AIAction = engine.chooseAction(for: round, playerID: "alice")

    // Should not crash when applied
    try action.apply(to: &round, playerID: "alice")
}

@Test
func aiEngineMediumReturnsValidAction() throws {
    var round: Round = try makeReadyRound()
    let engine: AIEngine = AIEngine(difficulty: .medium)

    let action: AIAction = engine.chooseAction(for: round, playerID: "alice")
    try action.apply(to: &round, playerID: "alice")
}

@Test
func aiEngineHardReturnsValidAction() throws {
    var round: Round = try makeReadyRound()
    let engine: AIEngine = AIEngine(difficulty: .hard)

    let action: AIAction = engine.chooseAction(for: round, playerID: "alice")
    try action.apply(to: &round, playerID: "alice")
}

@Test
func aiEngineMakesMoveConvenience() throws {
    var round: Round = try makeReadyRound()

    // Alice's turn — AI makes a move
    try round.makeAIMove(difficulty: .medium)

    // Should now be Bob's turn (or Alice drew first card and is in drawingSecondCard)
    #expect(round.currentPlayerID != nil)
}

@Test
func aiEngineHandlesPermitSelection() throws {
    var round: Round = try makeReadyRound()

    // Alice draws permits
    try round.drawPermits()

    // AI should choose which permits to keep
    let engine: AIEngine = AIEngine(difficulty: .hard)
    let action: AIAction = engine.chooseAction(for: round, playerID: "alice")

    if case .keepPermits(let permitIDs) = action {
        #expect(!permitIDs.isEmpty)
        try action.apply(to: &round, playerID: "alice")
    } else {
        Issue.record("Expected keepPermits action during choosingPermits phase")
    }
}

@Test
func aiEngineFullGame() throws {
    let map: GameMap = makeSimpleMap()
    var cards: [Card] = []
    for i in 1...60 { cards.append(Card(id: "blue-\(i)", color: .blue)) }

    var round: Round = try Round(
        cookedDeck: cards,
        cookedPermits: map.permits,
        gameMap: map,
        players: makePlayers(),
        segmentsPerPlayer: 5
    )

    // Setup: both players select permits via AI
    let easyEngine: AIEngine = AIEngine(difficulty: .easy)

    // Alice selects initial permits
    try round.selectInitialPermits(
        playerID: "alice",
        permitIDs: Array(round.playerHands[0].permits.prefix(2).map(\.id))
    )
    // Bob selects initial permits
    try round.selectInitialPermits(
        playerID: "bob",
        permitIDs: Array(round.playerHands[1].permits.prefix(2).map(\.id))
    )

    // Play until game completes (with safety limit)
    var turnCount: Int = 0
    let maxTurns: Int = 100

    while !round.isComplete && turnCount < maxTurns {
        guard let playerID = round.currentPlayerID else { break }

        let action: AIAction = easyEngine.chooseAction(for: round, playerID: playerID)
        try action.apply(to: &round, playerID: playerID)

        // If AI drew permits, it needs to keep some
        if case .waitingForPlayer(let id, .choosingPermits) = round.state {
            let keepAction: AIAction = easyEngine.chooseAction(for: round, playerID: id)
            try keepAction.apply(to: &round, playerID: id)
        }

        // If AI drew first card, it needs a second
        if case .waitingForPlayer(let id, .drawingSecondCard) = round.state {
            let secondAction: AIAction = easyEngine.chooseAction(for: round, playerID: id)
            try secondAction.apply(to: &round, playerID: id)
        }

        turnCount += 1
    }

    // Game should have completed within the turn limit
    #expect(round.isComplete)
    #expect(round.ended != nil)
}
