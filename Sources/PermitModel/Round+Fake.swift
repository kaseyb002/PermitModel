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
}
