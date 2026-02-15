import Foundation

// MARK: - Route Claimability

/// Describes whether a player can claim a route and why not if they cannot.
public enum RouteClaimability: Sendable {
    case claimable(cardIDs: [CardID])
    case needMoreSegments(has: Int, need: Int)
    case needMoreCards(routeColor: Route.Color, have: Int, need: Int)
    case routeAlreadyClaimed
    case doubleRouteBlocked
}

// MARK: - Round Extension

extension Round {
    /// Returns all routes the player can claim, with one valid card combination for each.
    public func claimableRoutes(for playerID: PlayerID) -> [(route: Route, cardIDs: [CardID])] {
        guard let hand = playerHand(for: playerID) else { return [] }
        let handCards: [Card] = hand.cards.compactMap { cardsMap[$0] }

        var results: [(route: Route, cardIDs: [CardID])] = []

        for route in routes {
            guard route.claimedBy == nil else { continue }
            guard hand.remainingSegments >= route.length else { continue }

            if let partnerID = route.doubleRoutePartnerID,
               let partner = routes.first(where: { $0.id == partnerID }) {
                if partner.claimedBy == playerID { continue }
                if playerHands.count <= 3 && partner.claimedBy != nil { continue }
            }

            if let cardIDs = findCardsForRoute(route: route, handCards: handCards) {
                results.append((route: route, cardIDs: cardIDs))
            }
        }

        return results
    }

    /// Returns the claimability status for a specific route.
    public func claimability(for route: Route, playerID: PlayerID) -> RouteClaimability {
        guard route.claimedBy == nil else { return .routeAlreadyClaimed }

        if let partnerID = route.doubleRoutePartnerID,
           let partner = routes.first(where: { $0.id == partnerID }) {
            if partner.claimedBy == playerID { return .doubleRouteBlocked }
            if playerHands.count <= 3 && partner.claimedBy != nil { return .doubleRouteBlocked }
        }

        guard let hand = playerHand(for: playerID) else {
            return .needMoreSegments(has: 0, need: route.length)
        }

        if hand.remainingSegments < route.length {
            return .needMoreSegments(has: hand.remainingSegments, need: route.length)
        }

        let handCards: [Card] = hand.cards.compactMap { cardsMap[$0] }
        if let cardIDs = findCardsForRoute(route: route, handCards: handCards) {
            return .claimable(cardIDs: cardIDs)
        }

        let (have, need) = countMatchingCardsForRoute(route: route, handCards: handCards)
        return .needMoreCards(routeColor: route.color, have: have, need: need)
    }

    // MARK: - Private Helpers

    private func findCardsForRoute(route: Route, handCards: [Card]) -> [CardID]? {
        let wildCards: [Card] = handCards.filter(\.isWild)
        let nonWildCards: [Card] = handCards.filter { !$0.isWild }

        if route.color == .any {
            let grouped: [CardColor: [Card]] = Dictionary(grouping: nonWildCards, by: \.color)
            for (_, cards) in grouped {
                if cards.count >= route.length {
                    return Array(cards.prefix(route.length).map(\.id))
                }
                if cards.count + wildCards.count >= route.length {
                    var selected: [CardID] = cards.map(\.id)
                    let wildsNeeded = route.length - cards.count
                    selected.append(contentsOf: wildCards.prefix(wildsNeeded).map(\.id))
                    return selected
                }
            }
            if wildCards.count >= route.length {
                return Array(wildCards.prefix(route.length).map(\.id))
            }
        } else {
            guard let requiredColor = routeColorToCardColor(route.color) else { return nil }
            let matching = nonWildCards.filter { $0.color == requiredColor }
            if matching.count >= route.length {
                return Array(matching.prefix(route.length).map(\.id))
            }
            if matching.count + wildCards.count >= route.length {
                var selected: [CardID] = matching.map(\.id)
                let wildsNeeded = route.length - matching.count
                selected.append(contentsOf: wildCards.prefix(wildsNeeded).map(\.id))
                return selected
            }
        }
        return nil
    }

    private func countMatchingCardsForRoute(route: Route, handCards: [Card]) -> (have: Int, need: Int) {
        let wildCards = handCards.filter(\.isWild)
        let nonWild = handCards.filter { !$0.isWild }

        if route.color == .any {
            let maxColorCount = Dictionary(grouping: nonWild, by: \.color)
                .mapValues(\.count)
                .values
                .max() ?? 0
            let totalUsable = maxColorCount + wildCards.count
            return (totalUsable, route.length)
        }

        guard let requiredColor = routeColorToCardColor(route.color) else {
            return (0, route.length)
        }
        let matchingCount = nonWild.filter { $0.color == requiredColor }.count
        let totalUsable = matchingCount + wildCards.count
        return (totalUsable, route.length)
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
}
