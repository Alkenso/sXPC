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

struct XPCPayload {
    let data: () throws -> Data
}

extension XPCPayload {
    static func encode<T: Encodable>(_ value: T) -> Self {
        .init { try JSONEncoder().encode(value) }
    }
}

internal struct XPCReply {
    let id = UUID()
    let reply: (_ processingQueue: DispatchQueue, _ finalQueue: DispatchQueue, Result<Data, Error>) -> Void
}

extension XPCReply {
    static func decode<T: Decodable>(_ type: T.Type, reply: @escaping (Result<T, Error>) -> Void) -> XPCReply {
        self.init { processingQueue, finalQueue, rawResult in
            processingQueue.async {
                let decodedResult = Result<T, Error> {
                    let data = try rawResult.get()
                    let value = try JSONDecoder().decode(T.self, from: data)
                    return value
                }
                finalQueue.async { reply(decodedResult) }
            }
        }
    }
}

@objc(sXPCTransportXPC)
internal protocol TransportXPC {
    func sendRequest(_ data: Data, receiveConfirmation: @escaping (Data?, Error?) -> Void)
    func sendReply(id: UUID, data: Data?, error: Error?)
}

extension XPCInterface {
    internal static var transport: XPCInterface<TransportXPC, TransportXPC> {
        .direct(interface: NSXPCInterface(with: TransportXPC.self))
    }
}
