import Foundation

// MARK: - Standard North America Map (Ticket to Ride / Permit to Wire)

extension GameMap {
    public static func standard() -> GameMap {
        GameMap(routes: Self.standardRoutes, permits: Self.standardPermits)
    }

    // MARK: - Routes

    // swiftlint:disable function_body_length
    static var standardRoutes: [Route] {
        [
            // Vancouver connections
            Route(id: 1, city1: .vancouver, city2: .calgary, length: 3, color: .any),
            Route(id: 2, city1: .vancouver, city2: .seattle, length: 1, color: .any, doubleRoutePartnerID: 3),
            Route(id: 3, city1: .vancouver, city2: .seattle, length: 1, color: .any, doubleRoutePartnerID: 2),

            // Calgary connections
            Route(id: 4, city1: .calgary, city2: .winnipeg, length: 6, color: .white),
            Route(id: 5, city1: .calgary, city2: .helena, length: 4, color: .any),

            // Seattle / Portland connections
            Route(id: 6, city1: .seattle, city2: .helena, length: 6, color: .yellow),
            Route(id: 7, city1: .seattle, city2: .portland, length: 1, color: .any, doubleRoutePartnerID: 8),
            Route(id: 8, city1: .seattle, city2: .portland, length: 1, color: .any, doubleRoutePartnerID: 7),
            Route(id: 9, city1: .portland, city2: .saltLakeCity, length: 6, color: .blue),
            Route(id: 10, city1: .portland, city2: .sanFrancisco, length: 5, color: .green, doubleRoutePartnerID: 11),
            Route(id: 11, city1: .portland, city2: .sanFrancisco, length: 5, color: .purple, doubleRoutePartnerID: 10),

            // Helena connections
            Route(id: 12, city1: .helena, city2: .winnipeg, length: 4, color: .blue),
            Route(id: 13, city1: .helena, city2: .duluth, length: 6, color: .orange),
            Route(id: 14, city1: .helena, city2: .denver, length: 4, color: .green),
            Route(id: 15, city1: .helena, city2: .saltLakeCity, length: 3, color: .purple),

            // Winnipeg connections
            Route(id: 16, city1: .winnipeg, city2: .duluth, length: 4, color: .black),
            Route(id: 17, city1: .winnipeg, city2: .saultStMarie, length: 6, color: .any),

            // Duluth connections
            Route(id: 18, city1: .duluth, city2: .saultStMarie, length: 3, color: .any),
            Route(id: 19, city1: .duluth, city2: .toronto, length: 6, color: .purple),
            Route(id: 20, city1: .duluth, city2: .chicago, length: 3, color: .red),
            Route(id: 21, city1: .duluth, city2: .omaha, length: 2, color: .any, doubleRoutePartnerID: 22),
            Route(id: 22, city1: .duluth, city2: .omaha, length: 2, color: .any, doubleRoutePartnerID: 21),

            // Sault St Marie connections
            Route(id: 23, city1: .saultStMarie, city2: .montreal, length: 5, color: .black),
            Route(id: 24, city1: .saultStMarie, city2: .toronto, length: 2, color: .any),

            // Toronto connections
            Route(id: 25, city1: .toronto, city2: .montreal, length: 3, color: .any),
            Route(id: 26, city1: .toronto, city2: .chicago, length: 4, color: .white),
            Route(id: 27, city1: .toronto, city2: .pittsburgh, length: 2, color: .any),

            // Montreal connections
            Route(id: 28, city1: .montreal, city2: .boston, length: 2, color: .any, doubleRoutePartnerID: 29),
            Route(id: 29, city1: .montreal, city2: .boston, length: 2, color: .any, doubleRoutePartnerID: 28),
            Route(id: 30, city1: .montreal, city2: .newYork, length: 3, color: .blue),

            // Boston connections
            Route(id: 31, city1: .boston, city2: .newYork, length: 2, color: .yellow, doubleRoutePartnerID: 32),
            Route(id: 32, city1: .boston, city2: .newYork, length: 2, color: .red, doubleRoutePartnerID: 31),

            // New York connections
            Route(id: 33, city1: .newYork, city2: .pittsburgh, length: 2, color: .white, doubleRoutePartnerID: 34),
            Route(id: 34, city1: .newYork, city2: .pittsburgh, length: 2, color: .green, doubleRoutePartnerID: 33),
            Route(id: 35, city1: .newYork, city2: .washington, length: 2, color: .orange, doubleRoutePartnerID: 36),
            Route(id: 36, city1: .newYork, city2: .washington, length: 2, color: .black, doubleRoutePartnerID: 35),

            // Pittsburgh connections
            Route(id: 37, city1: .pittsburgh, city2: .washington, length: 2, color: .any),
            Route(id: 38, city1: .pittsburgh, city2: .raleigh, length: 2, color: .any),
            Route(id: 39, city1: .pittsburgh, city2: .nashville, length: 4, color: .yellow),
            Route(id: 40, city1: .pittsburgh, city2: .saintLouis, length: 5, color: .green),
            Route(id: 41, city1: .pittsburgh, city2: .chicago, length: 3, color: .orange, doubleRoutePartnerID: 42),
            Route(id: 42, city1: .pittsburgh, city2: .chicago, length: 3, color: .black, doubleRoutePartnerID: 41),

            // Chicago connections
            Route(id: 43, city1: .chicago, city2: .omaha, length: 4, color: .blue),
            Route(id: 44, city1: .chicago, city2: .saintLouis, length: 2, color: .green, doubleRoutePartnerID: 45),
            Route(id: 45, city1: .chicago, city2: .saintLouis, length: 2, color: .white, doubleRoutePartnerID: 44),

            // Omaha connections
            Route(id: 46, city1: .omaha, city2: .denver, length: 4, color: .purple),
            Route(id: 47, city1: .omaha, city2: .kansasCity, length: 1, color: .any, doubleRoutePartnerID: 48),
            Route(id: 48, city1: .omaha, city2: .kansasCity, length: 1, color: .any, doubleRoutePartnerID: 47),

            // Denver connections
            Route(id: 49, city1: .denver, city2: .saltLakeCity, length: 3, color: .red, doubleRoutePartnerID: 50),
            Route(id: 50, city1: .denver, city2: .saltLakeCity, length: 3, color: .yellow, doubleRoutePartnerID: 49),
            Route(id: 51, city1: .denver, city2: .kansasCity, length: 4, color: .black, doubleRoutePartnerID: 52),
            Route(id: 52, city1: .denver, city2: .kansasCity, length: 4, color: .orange, doubleRoutePartnerID: 51),
            Route(id: 53, city1: .denver, city2: .oklahomaCity, length: 4, color: .red),
            Route(id: 54, city1: .denver, city2: .santaFe, length: 2, color: .any),
            Route(id: 55, city1: .denver, city2: .phoenix, length: 5, color: .white),

            // Salt Lake City connections
            Route(id: 56, city1: .saltLakeCity, city2: .sanFrancisco, length: 5, color: .orange, doubleRoutePartnerID: 57),
            Route(id: 57, city1: .saltLakeCity, city2: .sanFrancisco, length: 5, color: .white, doubleRoutePartnerID: 56),
            Route(id: 58, city1: .saltLakeCity, city2: .lasVegas, length: 3, color: .orange),

            // San Francisco connections
            Route(id: 59, city1: .sanFrancisco, city2: .losAngeles, length: 3, color: .yellow, doubleRoutePartnerID: 60),
            Route(id: 60, city1: .sanFrancisco, city2: .losAngeles, length: 3, color: .purple, doubleRoutePartnerID: 59),

            // Las Vegas / Los Angeles / Phoenix
            Route(id: 61, city1: .lasVegas, city2: .losAngeles, length: 2, color: .any),
            Route(id: 62, city1: .losAngeles, city2: .phoenix, length: 3, color: .any),
            Route(id: 63, city1: .losAngeles, city2: .elPaso, length: 6, color: .black),

            // Phoenix / Santa Fe / El Paso
            Route(id: 64, city1: .phoenix, city2: .santaFe, length: 3, color: .any),
            Route(id: 65, city1: .phoenix, city2: .elPaso, length: 3, color: .any),
            Route(id: 66, city1: .santaFe, city2: .elPaso, length: 2, color: .any),
            Route(id: 67, city1: .santaFe, city2: .oklahomaCity, length: 3, color: .blue),

            // Kansas City connections
            Route(id: 68, city1: .kansasCity, city2: .saintLouis, length: 2, color: .blue, doubleRoutePartnerID: 69),
            Route(id: 69, city1: .kansasCity, city2: .saintLouis, length: 2, color: .purple, doubleRoutePartnerID: 68),
            Route(id: 70, city1: .kansasCity, city2: .oklahomaCity, length: 2, color: .any, doubleRoutePartnerID: 71),
            Route(id: 71, city1: .kansasCity, city2: .oklahomaCity, length: 2, color: .any, doubleRoutePartnerID: 70),

            // Saint Louis connections
            Route(id: 72, city1: .saintLouis, city2: .nashville, length: 2, color: .any),
            Route(id: 73, city1: .saintLouis, city2: .littleRock, length: 2, color: .any),

            // Oklahoma City connections
            Route(id: 74, city1: .oklahomaCity, city2: .littleRock, length: 2, color: .any),
            Route(id: 75, city1: .oklahomaCity, city2: .dallas, length: 2, color: .any, doubleRoutePartnerID: 76),
            Route(id: 76, city1: .oklahomaCity, city2: .dallas, length: 2, color: .any, doubleRoutePartnerID: 75),

            // Nashville connections
            Route(id: 77, city1: .nashville, city2: .raleigh, length: 3, color: .black),
            Route(id: 78, city1: .nashville, city2: .atlanta, length: 1, color: .any),
            Route(id: 79, city1: .nashville, city2: .littleRock, length: 3, color: .white),

            // Raleigh / Washington connections
            Route(id: 80, city1: .raleigh, city2: .washington, length: 2, color: .any, doubleRoutePartnerID: 81),
            Route(id: 81, city1: .raleigh, city2: .washington, length: 2, color: .any, doubleRoutePartnerID: 80),
            Route(id: 82, city1: .raleigh, city2: .atlanta, length: 2, color: .any, doubleRoutePartnerID: 83),
            Route(id: 83, city1: .raleigh, city2: .atlanta, length: 2, color: .any, doubleRoutePartnerID: 82),
            Route(id: 84, city1: .raleigh, city2: .charleston, length: 2, color: .any),

            // Atlanta connections
            Route(id: 85, city1: .atlanta, city2: .charleston, length: 2, color: .any),
            Route(id: 86, city1: .atlanta, city2: .miami, length: 5, color: .blue),
            Route(id: 87, city1: .atlanta, city2: .newOrleans, length: 4, color: .yellow, doubleRoutePartnerID: 88),
            Route(id: 88, city1: .atlanta, city2: .newOrleans, length: 4, color: .orange, doubleRoutePartnerID: 87),

            // Little Rock connections
            Route(id: 89, city1: .littleRock, city2: .dallas, length: 2, color: .any),
            Route(id: 90, city1: .littleRock, city2: .newOrleans, length: 3, color: .green),

            // Dallas connections
            Route(id: 91, city1: .dallas, city2: .houston, length: 1, color: .any, doubleRoutePartnerID: 92),
            Route(id: 92, city1: .dallas, city2: .houston, length: 1, color: .any, doubleRoutePartnerID: 91),
            Route(id: 93, city1: .dallas, city2: .elPaso, length: 4, color: .red),

            // El Paso / Houston connections
            Route(id: 94, city1: .elPaso, city2: .houston, length: 6, color: .green),
            Route(id: 95, city1: .houston, city2: .newOrleans, length: 2, color: .any),

            // New Orleans / Miami / Charleston
            Route(id: 96, city1: .newOrleans, city2: .miami, length: 6, color: .red),
            Route(id: 97, city1: .charleston, city2: .miami, length: 4, color: .purple),
        ]
    }
    // swiftlint:enable function_body_length

    // MARK: - Permits (Destination Tickets)

    static var standardPermits: [Permit] {
        [
            Permit(id: 1, city1: .losAngeles, city2: .newYork, points: 21),
            Permit(id: 2, city1: .duluth, city2: .houston, points: 8),
            Permit(id: 3, city1: .saultStMarie, city2: .nashville, points: 8),
            Permit(id: 4, city1: .newYork, city2: .atlanta, points: 6),
            Permit(id: 5, city1: .portland, city2: .nashville, points: 17),
            Permit(id: 6, city1: .vancouver, city2: .montreal, points: 20),
            Permit(id: 7, city1: .duluth, city2: .elPaso, points: 10),
            Permit(id: 8, city1: .toronto, city2: .miami, points: 10),
            Permit(id: 9, city1: .portland, city2: .phoenix, points: 11),
            Permit(id: 10, city1: .dallas, city2: .newYork, points: 11),
            Permit(id: 11, city1: .calgary, city2: .saltLakeCity, points: 7),
            Permit(id: 12, city1: .calgary, city2: .phoenix, points: 13),
            Permit(id: 13, city1: .losAngeles, city2: .miami, points: 20),
            Permit(id: 14, city1: .winnipeg, city2: .littleRock, points: 11),
            Permit(id: 15, city1: .sanFrancisco, city2: .atlanta, points: 17),
            Permit(id: 16, city1: .kansasCity, city2: .houston, points: 5),
            Permit(id: 17, city1: .losAngeles, city2: .chicago, points: 16),
            Permit(id: 18, city1: .denver, city2: .pittsburgh, points: 11),
            Permit(id: 19, city1: .chicago, city2: .santaFe, points: 9),
            Permit(id: 20, city1: .vancouver, city2: .santaFe, points: 13),
            Permit(id: 21, city1: .boston, city2: .miami, points: 12),
            Permit(id: 22, city1: .chicago, city2: .newOrleans, points: 7),
            Permit(id: 23, city1: .montreal, city2: .atlanta, points: 9),
            Permit(id: 24, city1: .seattle, city2: .newYork, points: 22),
            Permit(id: 25, city1: .denver, city2: .elPaso, points: 4),
            Permit(id: 26, city1: .helena, city2: .losAngeles, points: 8),
            Permit(id: 27, city1: .winnipeg, city2: .houston, points: 12),
            Permit(id: 28, city1: .montreal, city2: .newOrleans, points: 13),
            Permit(id: 29, city1: .saultStMarie, city2: .oklahomaCity, points: 9),
            Permit(id: 30, city1: .seattle, city2: .losAngeles, points: 9),
        ]
    }
}
