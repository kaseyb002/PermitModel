import Foundation

public enum City: String, Equatable, Codable, Sendable, CaseIterable {
    case vancouver
    case calgary
    case seattle
    case portland
    case winnipeg
    case helena
    case duluth
    case saltLakeCity
    case sanFrancisco
    case saultStMarie
    case toronto
    case montreal
    case boston
    case newYork
    case pittsburgh
    case chicago
    case omaha
    case denver
    case lasVegas
    case losAngeles
    case phoenix
    case santaFe
    case elPaso
    case kansasCity
    case saintLouis
    case oklahomaCity
    case nashville
    case raleigh
    case washington
    case charleston
    case atlanta
    case miami
    case newOrleans
    case littleRock
    case dallas
    case houston

    public var displayableName: String {
        switch self {
        case .vancouver: "Vancouver"
        case .calgary: "Calgary"
        case .seattle: "Seattle"
        case .portland: "Portland"
        case .winnipeg: "Winnipeg"
        case .helena: "Helena"
        case .duluth: "Duluth"
        case .saltLakeCity: "Salt Lake City"
        case .sanFrancisco: "San Francisco"
        case .saultStMarie: "Sault St Marie"
        case .toronto: "Toronto"
        case .montreal: "Montreal"
        case .boston: "Boston"
        case .newYork: "New York"
        case .pittsburgh: "Pittsburgh"
        case .chicago: "Chicago"
        case .omaha: "Omaha"
        case .denver: "Denver"
        case .lasVegas: "Las Vegas"
        case .losAngeles: "Los Angeles"
        case .phoenix: "Phoenix"
        case .santaFe: "Santa Fe"
        case .elPaso: "El Paso"
        case .kansasCity: "Kansas City"
        case .saintLouis: "Saint Louis"
        case .oklahomaCity: "Oklahoma City"
        case .nashville: "Nashville"
        case .raleigh: "Raleigh"
        case .washington: "Washington"
        case .charleston: "Charleston"
        case .atlanta: "Atlanta"
        case .miami: "Miami"
        case .newOrleans: "New Orleans"
        case .littleRock: "Little Rock"
        case .dallas: "Dallas"
        case .houston: "Houston"
        }
    }
}
