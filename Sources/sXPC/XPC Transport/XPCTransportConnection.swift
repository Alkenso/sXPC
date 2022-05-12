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

private let clientHello = Data(UUID(staticString: "fef88fd3-9f29-4632-8827-0b417472c8f2").uuidString.utf8)
private let serverHello = Data(UUID(staticString: "071e1957-bf27-4669-961a-7e707b980740").uuidString.utf8)

public class XPCTransportConnection {
    public enum ConnectionState: Hashable, CaseIterable {
        /// Connection is performing initial handshake (initial connect or reconnect).
        /// Usually a good point to prepare/reset related program state
        ///
        /// Note: this state comes to 'stateHandler' on EACH reconnect attempt.
        /// This allows the client to drop connection is too many reconnects occur
        case connecting
        
        /// Connection is ready for use. It is OK to start message exchange
        case connected
        
        /// Connection is invalidated and closed. No messages with go though it
        case invalidated
    }
    
    private let connectionQueue = DispatchQueue(label: "XPCTransportConnection.connectionQueue")
    private var xpc: XPCConnectionInit?
    private let isClient: Bool
    private var serverActivation: (() -> Void)?
    private var connection: XPCConnection<TransportXPC, TransportXPC>
    
    public init(xpc: XPCConnectionInit) {
        switch xpc {
        case .service, .machService:
            self.xpc = xpc
        case .listenerEndpoint, .connection:
            self.xpc = nil
        }
        self.connection = XPCConnection(xpc, remoteInterface: .transport, exportedInterface: .transport)
        self.isClient = true
    }
    
    internal init(connection: XPCConnection<TransportXPC, TransportXPC>) {
        self.xpc = nil
        self.connection = connection
        self.isClient = false
    }
    
    deinit {
        serverActivation?()
        connection.invalidate()
    }
    
    // Properties to be set BEFORE 'activate'. Overriding them after 'activate' leads to undefined behaviour
    public var stateHandler: ((ConnectionState) -> Void)?
    public var receiveDataHandler: XPCTransportReceiveDataHandler?
    public var queue = DispatchQueue(label: "XPCTransportConnection.queue")
    
    @Atomic public private(set)var state: ConnectionState?
    
    /// Unique ID of the connection
    /// `peerID` is the same for both client and server parts of the same connection
    public private(set) var peerID = UUID()
    
    /// Additional payload of the connection exchanged during handshake.
    /// Can be set on the **client** side to pass some specific information to the server side.
    ///
    /// `peerUserInfo` is the same for both client and server parts of the same connection
    public var peerUserInfo = Data()
    
    
    public func activate() {
        // On the listener side, `activate` is called twice:
        // 1. When XPCListener receives new connection,
        //    transport activation performs handshake and suspends the connection
        // 2. When the listener's client setup transport and ready to start using it
        
        if let serverActivation = serverActivation {
            serverActivation()
            self.serverActivation = nil
        }
        
        if let state = self.state {
            updateState(state)
            return
        }
        prepareAndResume(connection: connection)
    }
    
    public func invalidate() {
        queue.async {
            self.xpc = nil
            self.connection.invalidate()
        }
    }
    
    public func send(_ payload: XPCPayload, reply: XPCReply) {
        connectionQueue.async {
            var replyEx = reply
            replyEx.processingQueue = self.connectionQueue
            replyEx.finalQueue = self.queue
            
            guard self.state != nil else {
                replyEx(.failure(CommonError.unexpected("Failed to send data: transport connection is not activated")))
                return
            }
            
            do {
                let data = try payload.data()
                self.connection
                    .remoteObjectProxy { replyEx(.failure($0)) }
                    .send(data) { replyEx(Result(success: $0.flatMap(XPCPayload.raw), failure: $1)) }
            } catch {
                replyEx(.failure(error))
            }
        }
    }
    
    fileprivate func receiveData(_ data: Data, reply: @escaping (Data?, Error?) -> Void) {
        guard !receiveClientHello(data, reply: reply) else { return }
        connectionQueue.async { self.receiveMessageData(data, reply: reply) }
    }
    
    private func receiveMessageData(_ data: Data, reply: @escaping (Data?, Error?) -> Void) {
        guard let receiveDataHandler = receiveDataHandler else {
            reply(nil, CommonError.fatal("Receiving is not implemented"))
            return
        }
        
        var replyEx = XPCReply {
            switch $0 {
            case .success(let replyData):
                reply(replyData, nil)
            case .failure(let replyError):
                reply(nil, replyError)
            }
        }
        replyEx.processingQueue = connectionQueue
        replyEx.finalQueue = nil
        receiveDataHandler.handler(queue, peerID, data, replyEx)
    }
    
    private func updateState(_ state: ConnectionState) {
        self.state = state
        queue.async {
            self.stateHandler?(state)
        }
    }
    
    private func reconnect() {
        connectionQueue.async {
            guard let xpc = self.xpc else {
                self.updateState(.invalidated)
                return
            }
            self.connection = XPCConnection(xpc, remoteInterface: .transport, exportedInterface: .transport)
            self.prepareAndResume(connection: self.connection)
        }
    }
    
    private func prepareAndResume(connection: XPCConnection<TransportXPC, TransportXPC>) {
        updateState(.connecting)
        
        let exportedObject = ExportedObject(connection: Weak(self))
        connection.exportedObject = exportedObject
        connection.interruptionHandler = { [weak connection] in
            connection?.invalidate()
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            connection?.invalidationHandler = nil
            self?.reconnect()
        }
        
        connection.resume()
        
        if isClient {
            sendClientHello()
        }
    }
    
    private func sendClientHello() {
        let helloData = clientHello + Data(pod: peerID.uuid) + peerUserInfo
        connection.remoteObjectProxy.send(helloData) { response, error in
            self.connectionQueue.async {
                if response == serverHello {
                    self.updateState(.connected)
                } else if error != nil {
                    self.connection.invalidate()
                } else {
                    self.invalidate()
                }
            }
        }
    }
    
    private func receiveClientHello(_ data: Data, reply: @escaping (Data?, Error?) -> Void) -> Bool {
        guard !isClient, state != .connected, data.starts(with: clientHello) else {
            return false
        }
        guard let realPeerID = data.dropFirst(clientHello.count).pod(exactly: uuid_t.self).flatMap(UUID.init(uuid:)) else {
            reply(nil, CommonError.invalidArgument(
                arg: "Client Hello",
                invalidValue: data,
                description: "Failed to parse peer ID from client hello (count = \(data.count))")
            )
            return true
        }
        
        peerID = realPeerID
        peerUserInfo = data.dropFirst(clientHello.count).dropFirst(MemoryLayout<uuid_t>.stride)
        updateState(.connected)
        
        connection.suspend()
        serverActivation = connection.resume
        reply(serverHello, nil)
        
        return true
    }
}


@objc
private class ExportedObject: NSObject, TransportXPC {
    private let receiveDataHandler: (Data, @escaping (Data?, Error?) -> Void) -> Void
    
    init(connection: Weak<XPCTransportConnection>) {
        receiveDataHandler = { data, reply in
            guard let instance = connection.value else {
                reply(nil, CommonError.unexpected("Connection is died"))
                return
            }
            instance.receiveData(data, reply: reply)
        }
    }
    
    func send(_ data: Data, reply: @escaping (Data?, Error?) -> Void) {
        receiveDataHandler(data, reply)
    }
}

extension XPCTransportConnection.ConnectionState: CustomStringConvertible {
    public var description: String { "\(self)" }
}
