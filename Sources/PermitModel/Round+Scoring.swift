import Foundation

extension Round {
    public func isPermitCompleted(permit: Permit, playerID: PlayerID) -> Bool {
        let playerRoutes: [Route] = routes.filter { $0.claimedBy == playerID }

        // Build adjacency list from player's claimed routes
        var adjacency: [City: Set<City>] = [:]
        for route in playerRoutes {
            adjacency[route.city1, default: []].insert(route.city2)
            adjacency[route.city2, default: []].insert(route.city1)
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

    public func longestContinuousPath(for playerID: PlayerID) -> Int {
        let playerRoutes: [Route] = routes.filter { $0.claimedBy == playerID }
        if playerRoutes.isEmpty { return 0 }

        // Build adjacency list with route info (edges can be traversed once each)
        var adjacency: [City: [(city: City, routeID: RouteID, length: Int)]] = [:]
        for route in playerRoutes {
            adjacency[route.city1, default: []].append((city: route.city2, routeID: route.id, length: route.length))
            adjacency[route.city2, default: []].append((city: route.city1, routeID: route.id, length: route.length))
        }

        var maxLength: Int = 0
        let cities: Set<City> = Set(playerRoutes.flatMap { [$0.city1, $0.city2] })

        for city in cities {
            var usedRoutes: Set<RouteID> = []
            dfsLongestPath(
                city: city,
                adjacency: adjacency,
                usedRoutes: &usedRoutes,
                currentLength: 0,
                maxLength: &maxLength
            )
        }

        return maxLength
    }

    private func dfsLongestPath(
        city: City,
        adjacency: [City: [(city: City, routeID: RouteID, length: Int)]],
        usedRoutes: inout Set<RouteID>,
        currentLength: Int,
        maxLength: inout Int
    ) {
        maxLength = max(maxLength, currentLength)

        for edge in adjacency[city] ?? [] {
            if !usedRoutes.contains(edge.routeID) {
                usedRoutes.insert(edge.routeID)
                dfsLongestPath(
                    city: edge.city,
                    adjacency: adjacency,
                    usedRoutes: &usedRoutes,
                    currentLength: currentLength + edge.length,
                    maxLength: &maxLength
                )
                usedRoutes.remove(edge.routeID)
            }
        }
    }

    func playersWithLongestPath() -> [PlayerID] {
        var maxPath: Int = 0
        var winners: [PlayerID] = []

        for hand in playerHands {
            let pathLength: Int = longestContinuousPath(for: hand.player.id)
            if pathLength > maxPath {
                maxPath = pathLength
                winners = [hand.player.id]
            } else if pathLength == maxPath && maxPath > 0 {
                winners.append(hand.player.id)
            }
        }

        return winners
    }
}
