import Foundation

public enum JungleRouteCompletion {
    public static func shouldClose(route: String, activeLevel: Int, gameTime: Double) -> Bool {
        guard gameTime.isFinite, gameTime >= 90 else { return false }
        switch route {
        case "fullClear": return activeLevel >= 4
        case "levelThree", "invade": return activeLevel >= 3
        default: return false
        }
    }
}
