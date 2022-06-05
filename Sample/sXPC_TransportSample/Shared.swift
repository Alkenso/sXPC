import Foundation
import sXPC

// MARK: TokenService public routines

public enum RemoteNotification: Codable {
    case notify(String)
    case askApproval(XPCTransportMessage</* request: text */ String, /* reply: isApprovedByUser */ Bool>)
}

public struct AnalyticEvent: Codable {
    var reason: String
    var date: Date
}
