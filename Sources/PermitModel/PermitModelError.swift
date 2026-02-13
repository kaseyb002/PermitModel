import Foundation

public enum PermitModelError: Error, Equatable, Sendable {
    case notEnoughPlayers
    case tooManyPlayers
    case notInSetupPhase
    case notWaitingForPlayerToAct
    case notInChoosingActionPhase
    case notInDrawingSecondCardPhase
    case notInChoosingPermitsPhase
    case playerNotFound
    case routeNotFound
    case routeAlreadyClaimed
    case insufficientCards
    case invalidCardColor
    case cardNotInHand
    case cardNotFound
    case invalidFaceUpIndex
    case noCardsAvailable
    case notEnoughSegments
    case cannotClaimBothDoubleRoutes
    case doubleRouteBlockedInSmallGame
    case noPermitsAvailable
    case mustKeepAtLeastOnePermit
    case mustKeepAtLeastTwoInitialPermits
    case invalidPermitSelection
    case gameIsComplete
    case cannotDrawFiberAsSecondCard
}
