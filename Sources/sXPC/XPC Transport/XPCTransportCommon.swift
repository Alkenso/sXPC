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

public struct XPCPayload {
    public let data: () throws -> Data
    
    public init(data: @escaping () throws -> Data) {
        self.data = data
    }
}

extension XPCPayload {
    public static func raw(_ data: Data) -> Self {
        .init { data }
    }
}
 
extension XPCPayload {
    public static func encode<T: Encodable>(_ value: T) -> Self {
        .init { try JSONEncoder().encode(value) }
    }
    
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: data())
    }
}


public struct XPCReply {
    private let reply: (_ processingQueue: DispatchQueue?, _ finalQueue: DispatchQueue?, Result<Data, Error>) -> Void
    internal var processingQueue: DispatchQueue?
    internal var finalQueue: DispatchQueue?
}

extension XPCReply { //user
    public init(reply: @escaping (Result<Data, Error>) -> Void) {
        self.init { _, finalQueue, result in
            finalQueue.execute { reply(result) }
        }
    }
    
    public static func decode<T: Decodable>(
        _ type: T.Type,
        decoder: @escaping (Data) throws -> T,
        reply: @escaping (Result<T, Error>) -> Void
    ) -> XPCReply {
        self.init { processingQueue, finalQueue, result in
            processingQueue.execute {
                let decodedResult = Result<T, Error> {
                    let data = try result.get()
                    let value = try decoder(data)
                    return value
                }
                finalQueue.execute { reply(decodedResult) }
            }
        }
    }
    
    public static func decode<T: Decodable>(_ type: T.Type, reply: @escaping (Result<T, Error>) -> Void) -> XPCReply {
        .decode(type, decoder: { try XPCPayload.raw($0).decode(T.self) }, reply: reply)
    }
    
    public func callAsFunction(_ result: Result<XPCPayload, Error>) {
        processingQueue.execute {
            do {
                let data = try result.get().data()
                reply(nil, finalQueue, .success(data))
            } catch {
                reply(nil, finalQueue, .failure(error))
            }
        }
    }
    
    public func callAsFunction(_ success: XPCPayload) {
        self(.success(success))
    }
    
    public func callAsFunction(_ error: Error) {
        self(.failure(error))
    }
}

private extension Optional where Wrapped == DispatchQueue {
    func execute(work: @escaping () -> Void) {
        if let queue = self {
            queue.async(execute: work)
        } else {
            work()
        }
    }
}


public struct XPCTransportPeer: Hashable {
    public var id: UUID
    public var userInfo: Data
    
    public init(id: UUID, userInfo: Data) {
        self.id = id
        self.userInfo = userInfo
    }
}

public struct XPCTransportReceiveDataHandler {
    internal let handler: (DispatchQueue, XPCTransportPeer, Data, XPCReply) -> Void
}

extension XPCTransportReceiveDataHandler {
    public init(handler: @escaping (XPCTransportPeer, Data, XPCReply) -> Void) {
        self.init { queue, id, data, reply in
            queue.async { handler(id, data, reply) }
        }
    }
    
    public static func decode<T: Decodable>(_ type: T.Type, handler: @escaping (XPCTransportPeer, T, XPCReply) -> Void) -> Self {
        decode(type, decoder: { try XPCPayload.raw($0).decode(T.self) }, handler: handler)
    }
    
    public static func decode<T: Decodable>(_ type: T.Type, decoder: @escaping (Data) throws -> T, handler: @escaping (XPCTransportPeer, T, XPCReply) -> Void) -> Self {
        self.init { queue, id, data, reply in
            do {
                let value = try decoder(data)
                queue.async { handler(id, value, reply) }
            } catch {
                reply(.failure(error))
            }
        }
    }
}

@objc(sXPCTransportXPC)
internal protocol TransportXPC {
    func send(_ data: Data, reply: @escaping (_ response: Data?, _ error: Error?) -> Void)
}

extension XPCInterface {
    internal static var transport: XPCInterface<TransportXPC, TransportXPC> {
        .direct(interface: NSXPCInterface(with: TransportXPC.self))
    }
}
