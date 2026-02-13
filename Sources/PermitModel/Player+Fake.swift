import Foundation

extension Player {
    public static func fake(
        id: PlayerID = UUID().uuidString,
        name: String = "Player",
        imageURL: URL? = nil,
        score: Int = 0,
        color: PlayerColor = .blue
    ) -> Player {
        Player(
            id: id,
            name: name,
            imageURL: imageURL,
            score: score,
            color: color
        )
    }
}
