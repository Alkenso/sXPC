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

/// XPCTransportServer listens for incoming connections, manages them and
/// provide interfaces to send and receive messages.
/// XPCTransportServer performs all job of maintaining connection lifecycle.
public class XPCTransportServer {
    private let listener: XPCTransportListener
    private let connections = Synchronized<[UUID: XPCTransportConnection]>(.serial)
    
    public init(_ xpcInit: XPCListenerInit) {
        self.listener = .init(xpcInit)
    }
    
    public var queue = DispatchQueue(label: "XPCTransportServer.queue")
    public var connectionOpened: ((UUID) -> Void)?
    public var connectionClosed: ((UUID) -> Void)?
    public var receiveDataHandler: XPCTransportReceiveDataHandler?
    public var verifyConnectionHandler: ((audit_token_t) -> Bool)? {
        get { listener.verifyConnectionHandler }
        set { listener.verifyConnectionHandler = newValue }
    }
    public var activeConnections: [UUID] { Array(connections.read(\.keys)) }
    
    public func activate() {
        listener.newConnectionHandler = { [weak self] in self?.handleNewConnection($0) }
        listener.activate()
    }
    
    public func invalidate() {
        listener.invalidate()
    }
    
    public func send(to peer: UUID, payload: XPCPayload, reply: XPCReply) {
        if let connection = connections.read({ $0[peer] }) {
            connection.send(payload, reply: reply)
        } else {
            reply(.failure(CommonError.notFound(what: "Connection", value: peer, where: "transport connections")))
        }
    }
    
    private func handleNewConnection(_ transport: XPCTransportConnection) {
        let id = transport.peerID
        transport.queue = queue
        transport.stateHandler = { [weak self] connectionState in
            guard let self = self else { return }
            switch connectionState {
            case .connected:
                self.connectionOpened?(id)
            case .invalidated:
                self.connectionClosed?(id)
                self.connections.writeAsync { $0.removeValue(forKey: id) }
            case .connecting:
                break
            }
        }
        transport.receiveDataHandler = receiveDataHandler
        
        connections.writeAsync { $0[id] = transport }
        transport.activate()
    }
}


/// XPCTransportListener listens for incoming connections and forward them to the caller
public class XPCTransportListener {
    private let listener: XPCListener<TransportXPC, TransportXPC>
    
    public init(_ xpcInit: XPCListenerInit) {
        self.listener = XPCListener(xpcInit, exportedInterface: .transport, remoteInterface: .transport)
    }
    
    public var queue = DispatchQueue(label: "XPCTransportListener.queue")
    public var newConnectionHandler: ((XPCTransportConnection) -> Void)?
    public var verifyConnectionHandler: ((audit_token_t) -> Bool)? {
        get { listener.verifyConnectionHandler }
        set { listener.verifyConnectionHandler = newValue }
    }
    
    public func activate() {
        listener.newConnectionHandler = { [weak self] in
            guard self?.newConnectionHandler != nil else { return false }
            self?.handleNewConnection($0)
            return true
        }
        
        listener.resume()
    }
    
    public func invalidate() {
        listener.invalidate()
    }
    
    private func handleNewConnection(_ connection: XPCConnection<TransportXPC, TransportXPC>) {
        // Activate transport and wait till it become connected or invalid
        // Connected transport on listener side remains 'inactivated' and
        // may can be setup, activated and used
        
        let transport = XPCTransportConnection(connection: connection)
        transport.stateHandler = { [weak self] in
            switch $0 {
            case .connected:
                transport.stateHandler = nil
                self?.newConnectionHandler?(transport)
            case .invalidated:
                transport.stateHandler = nil
            case .connecting:
                break
            }
        }
        transport.activate()
    }
}
