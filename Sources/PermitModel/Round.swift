import Foundation

public struct Round: Equatable, Codable, Sendable {
    // MARK: - Constants

    public static let maxLogActions: Int = 100
    public static let initialSegments: Int = 45
    public static let initialHandSize: Int = 4
    public static let faceUpCount: Int = 5
    public static let initialPermitCount: Int = 3
    public static let minInitialPermitsToKeep: Int = 2
    public static let finalRoundSegmentThreshold: Int = 2

    // MARK: - Initialized Properties

    public let id: String
    public let started: Date

    // MARK: - Game State

    public internal(set) var state: State
    public internal(set) var cardsMap: [CardID: Card]
    public internal(set) var drawPile: [CardID]
    public internal(set) var discardPile: [CardID]
    public internal(set) var faceUpCards: [CardID]
    public internal(set) var playerHands: [PlayerHand]
    public internal(set) var routes: [Route]
    public internal(set) var permitDeck: [Permit]

    // MARK: - Final Round

    public internal(set) var finalRoundTriggeredBy: PlayerID?
    public internal(set) var turnsRemainingInFinalRound: Int?

    // MARK: - Results

    public internal(set) var log: [Action]
    public internal(set) var ended: Date?

    // MARK: - State

    public enum State: Equatable, Codable, Sendable {
        case setup(pendingPermitSelections: [PlayerID])
        case waitingForPlayer(id: PlayerID, phase: TurnPhase)
        case gameComplete(winner: Player)

        public var logValue: String {
            switch self {
            case .setup:
                "Setting up game"
            case .waitingForPlayer(let id, let phase):
                "Waiting for player \(id) (\(phase))"
            case .gameComplete(let winner):
                "\(winner.name) won the game with \(winner.score) points."
            }
        }
    }

    // MARK: - Turn Phase

    public enum TurnPhase: Equatable, Codable, Sendable {
        case choosingAction
        case drawingSecondCard(firstCardId: CardID, firstDrawSource: DrawSource)
        case choosingPermits(drawn: [Permit])
    }

    // MARK: - Draw Source

    public enum DrawSource: Equatable, Codable, Sendable {
        case faceUp(index: Int)
        case drawPile
    }

    // MARK: - Action Log

    /// A single drawn card and where it was drawn from (for log display).
    public struct DrawnCard: Equatable, Codable, Sendable {
        public let cardID: CardID
        public let source: DrawSource

        public init(cardID: CardID, source: DrawSource) {
            self.cardID = cardID
            self.source = source
        }
    }

    public struct Action: Equatable, Codable, Sendable {
        public let playerID: PlayerID
        public let decision: Decision
        public let timestamp: Date

        public enum Decision: Equatable, Codable, Sendable {
            case drawCards([DrawnCard])
            case claimRoute(routeId: RouteID, cardIds: [CardID], points: Int)
            case drawPermits(keptPermitIds: [PermitID])
        }

        public enum CodingKeys: String, CodingKey {
            case playerID = "playerId"
            case decision
            case timestamp
        }

        public init(
            playerID: PlayerID,
            decision: Decision,
            timestamp: Date = .now
        ) {
            self.playerID = playerID
            self.decision = decision
            self.timestamp = timestamp
        }
    }
}
