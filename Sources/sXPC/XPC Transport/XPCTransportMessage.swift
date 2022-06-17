/*
 * MIT License
 *
 * Copyright (c) 2022 Alkenso (Vladimir Vashurkin)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import Foundation
import SwiftConvenience

public struct XPCVoid: Codable {}

public struct XPCTransportMessage<Request: Codable, Response: Codable> {
    private let replyAction: (Result<Response, Error>) -> Void
    
    /// Message request
    public let request: Request
    
    /// Reply to message
    public func reply(_ result: Result<Response, Error>) {
        replyAction(result)
    }
    
    /// Create `XPCTransportMessage` instance
    /// - Parameters:
    ///     - request: `Encodable` type to be sent to another party
    ///     - reply: action to be called when another party responds
    /// - Warning: `reply` action MUST NOT deal with `XPCTransportMessage` type: it is unsupported and error-prone
    public init(request: Request, reply: @escaping (Result<Response, Error>) -> Void) {
        self.request = request
        self.replyAction = reply
    }
    
    private enum CodingKeys: String, CodingKey {
        case request
        case replyID
    }
}

extension XPCTransportMessage {
    public init(reply: @escaping (Result<Response, Error>) -> Void) where Request == XPCVoid {
        self.init(request: XPCVoid(), reply: reply)
    }
    
    /// Reply to message
    public func reply() where Response == XPCVoid {
        reply(.success(XPCVoid()))
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
        
        let replyDrop = DeinitAction {
            let error = CommonError.unexpected("XPCTransportMessage has been dropped without calling reply")
            replySender(replyID, .failure(error))
        }
        replyAction = {
            replyDrop.release()
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
