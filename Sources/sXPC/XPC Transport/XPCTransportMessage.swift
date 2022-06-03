//
//  File.swift
//  
//
//  Created by Alkenso (Vladimir Vashurkin) on 03.06.2022.
//

import Foundation
import SwiftConvenience

public struct XPCVoid: Codable {}

public struct XPCTransportMessage<Request: Codable, Response: Codable> {
    public var request: Request
    public var reply: (Result<Response, Error>) -> Void
    
    /// Create `XPCTransportMessage` instance
    /// - Parameters:
    ///     - request: `Encodable` type to be sent to another party
    ///     - reply: action to be called when another party responds
    /// - Warning: `reply` action MUST NOT deal with `XPCTransportMessage` type: it is unsupported and error-prone
    public init(request: Request, reply: @escaping (Result<Response, Error>) -> Void) {
        self.request = request
        self.reply = reply
    }
    
    private enum CodingKeys: String, CodingKey {
        case request
        case replyID
    }
}

extension XPCTransportMessage {
    public init(reply: @escaping (Result<Response, Error>) -> Void) where Request == XPCVoid {
        self.request = XPCVoid()
        self.reply = reply
    }
}

extension XPCTransportMessage: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(Request.self, forKey: .request)
        let replyID = try container.decode(UUID.self, forKey: .replyID)
        guard let replySender = decoder.userInfo[.replySender] as? XPCTransportMessageReplySender else {
            throw CommonError.unexpected("Missing XPCTransport-related userInfo. Decoding `XPCTransportMessage` out of `XPCTransportConnection` internals is not supported. Note that using `XPCTransportMessage` in reply action is not supported and may lead to this error")
        }
        reply = {
            replySender(replyID, $0.map { .encode($0) })
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        guard let replyCollector = encoder.userInfo[.replyCollector] as? XPCTransportMessageReplyCollector else {
            throw CommonError.unexpected("Missing XPCTransport-related userInfo. Encoding `XPCTransportMessage` out of `XPCTransportConnection` internals is not supported. Note that using `XPCTransportMessage` in reply action is not supported and may lead to this error")
        }
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request, forKey: .request)
        
        let xpcReply = XPCReply.decode(Response.self, reply: reply)
        try container.encode(xpcReply.id, forKey: .replyID)
        replyCollector(xpcReply)
    }
}


internal typealias XPCTransportMessageReplySender = (UUID, Result<XPCPayload, Error>) -> Void
internal typealias XPCTransportMessageReplyCollector = (XPCReply) -> Void

extension CodingUserInfoKey {
    internal static let replySender = CodingUserInfoKey(rawValue: "sXPC.XPCReplySender")!
    internal static let replyCollector = CodingUserInfoKey(rawValue: "sXPC.XPCReplyCollector")!
}
