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
import SpellbookFoundation

private let clientHello = Data(UUID(staticString: "fef88fd3-9f29-4632-8827-0b417472c8f2").uuidString.utf8)
private let serverHello = Data(UUID(staticString: "071e1957-bf27-4669-961a-7e707b980740").uuidString.utf8)

public struct XPCTransportPeer: Hashable {
    public var id: UUID
    public var userInfo: Data
    public var auditToken: audit_token_t
    
    public init(id: UUID, userInfo: Data, auditToken: audit_token_t) {
        self.id = id
        self.userInfo = userInfo
        self.auditToken = auditToken
    }
}

public enum XPCTransportConnectionState: String, Hashable, CaseIterable {
    /// Connection is performing initial handshake (initial connect or reconnect).
    /// Usually a good point to prepare/reset related program state
    ///
    /// Note: this state comes to 'stateHandler' on EACH reconnect attempt.
    /// This allows the client to drop connection if too many reconnects occur
    case connecting
    
    /// Connection is ready for use. It is OK to start message exchange
    case connected
    
    /// Connection is invalidated and closed. No messages will go though it
    case invalidated
}

public class XPCTransportConnection {
    private let connectionQueue = DispatchQueue(label: "XPCTransportConnection.connection.queue")
    private var messageQueue = DispatchQueue(label: "XPCTransportConnection.message.queue")
    private var xpc: XPCConnectionInit?
    private let isClient: Bool
    private var serverActivation: (() -> Void)?
    private var connection: XPCConnection<TransportXPC, TransportXPC>
    private var receiveDataHandler: ((Data) throws -> Void)?
    private var pendingReplies: [UUID: XPCReply] = [:]
    
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
    public var queue = DispatchQueue(label: "XPCTransportConnection.queue")
    public var stateHandler: ((XPCTransportConnectionState) -> Void)?
    
    public func setReceiveMessageHandler<Message: Decodable>(_ type: Message.Type = Message.self, handler: @escaping (Message) -> Void) {
        let decoder = JSONDecoder()
        decoder.userInfo[.replySender] = { [weak self] in self?.sendReply(id: $0, response: $1) } as XPCTransportMessageReplySender
        
        receiveDataHandler = { [queue] in
            let value = try decoder.decode(Message.self, from: $0)
            queue.async { handler(value) }
        }
    }
    
    @Atomic public private(set) var state: XPCTransportConnectionState?
    @Atomic public private(set) var connectionToken: audit_token_t?
    
    /// Unique ID of the connection
    /// `peerID` is the same for both client and server parts of the same connection
    public private(set) var peerID = UUID()
    
    /// Additional payload of the connection exchanged during handshake.
    /// Can be set on the **client** side to pass some specific information to the server side.
    ///
    /// `peerUserInfo` is the same for both client and server parts of the same connection
    public var peerUserInfo = Data()
    
    /// Delay between reconnect attempts if connection is dropped. Specify `nil` to disable reconnect at all
    public var reconnectDelay: TimeInterval? = 0.5
    
    public func activate() {
        // On the listener side, `activate` is called twice:
        // 1. When XPCListener receives new connection,
        //    transport activation performs handshake and suspends the connection
        // 2. When the listener's client setup transport and ready to start to use it
        
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
    
    public func send<Message: Encodable>(_ message: Message) throws {
        try connectionQueue.sync {
            guard state != nil else {
                throw CommonError.unexpected("Send failed: transport connection is not activated")
            }
            
            let encoder = JSONEncoder()
            var replies: [XPCReply] = []
            encoder.userInfo[.replyCollector] = { replies.append($0) } as XPCTransportMessageReplyCollector
            
            let data = try encoder.encode(message)
            replies.forEach { pendingReplies[$0.id] = $0 }
            
            let replyIDs = replies.map(\.id)
            self.connection
                .remoteObjectProxy { [weak self] in self?.fulfillPendingReply(to: replyIDs, with: .failure($0)) }
                .sendRequest(data) { [weak self] _, error in
                    if let error = error {
                        self?.fulfillPendingReply(to: replyIDs, with: .failure(error))
                    }
                }
        }
    }
    
    private func sendReply(id: UUID, response: Result<XPCPayload, Error>) {
        messageQueue.async {
            let result = response.flatMap { value in Result { try value.data() } }
            self.connectionQueue.async {
                self.connection
                    .remoteObjectProxy()
                    .sendReply(id: id, data: result.success, error: result.failure)
            }
        }
    }
    
    fileprivate func receiveRequest(_ data: Data, confirmation: @escaping (Data?, Error?) -> Void) {
        guard !receiveClientHello(data, reply: confirmation) else { return }
        
        messageQueue.async {
            guard let receiveDataHandler = self.receiveDataHandler else {
                confirmation(nil, CommonError.fatal("Receiving is not implemented"))
                return
            }
            
            do {
                try receiveDataHandler(data)
                confirmation(nil, nil)
            } catch {
                confirmation(nil, error)
            }
        }
    }
    
    fileprivate func receiveReply(id: UUID, response: Result<Data, Error>) {
        fulfillPendingReply(to: [id], with: response)
    }
    
    private func fulfillPendingReply(to ids: [UUID], with response: Result<Data, Error>) {
        connectionQueue.async {
            let replys = ids.compactMap { self.pendingReplies.removeValue(forKey: $0) }
            replys.forEach { $0.reply(self.messageQueue, self.queue, response) }
        }
    }
    
    private func sendClientHello() {
        let helloData = clientHello + Data(pod: peerID.uuid) + peerUserInfo
        connection.remoteObjectProxy().sendRequest(helloData) { response, error in
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
        
        do {
            var reader = BinaryReader(data: data)
            try reader.skip(clientHello.count)
            peerID = UUID(uuid: try reader.read())
            
            peerUserInfo = try reader.read(maxCount: .max)
            updateState(.connected)
            
            connection.suspend()
            serverActivation = connection.resume
            reply(serverHello, nil)
        } catch {
            reply(
                nil,
                CommonError.invalidArgument(
                    arg: "Client Hello",
                    invalidValue: data,
                    description: "Failed to parse client hello from data (count = \(data.count)). Error: \(error)"
                )
            )
        }
        
        return true
    }
    
    private func updateState(_ state: XPCTransportConnectionState) {
        connectionToken = state == .connected ? connection.native.auditToken : nil
        self.state = state
        queue.async {
            self.stateHandler?(state)
        }
    }
    
    private func reconnect() {
        connectionQueue.async {
            guard let xpc = self.xpc, let reconnectDelay = self.reconnectDelay else {
                self.updateState(.invalidated)
                return
            }
            self.connectionQueue.asyncAfter(deadline: .now() + reconnectDelay) {
                self.connection = XPCConnection(xpc, remoteInterface: .transport, exportedInterface: .transport)
                self.prepareAndResume(connection: self.connection)
            }
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
}

extension XPCTransportConnection: CustomDebugStringConvertible {
    public var debugDescription: String {
        "XPCTransportConnection { peerID = \(peerID), peerUserInfo = \(peerUserInfo.base64EncodedString()), state = \(state?.description ?? "nil") }"
    }
}

extension XPCTransportConnectionState: CustomStringConvertible {
    public var description: String { rawValue }
}

@objc
private class ExportedObject: NSObject, TransportXPC {
    private let connection: Weak<XPCTransportConnection>
    
    init(connection: Weak<XPCTransportConnection>) {
        self.connection = connection
    }
    
    func sendRequest(_ data: Data, receiveConfirmation: @escaping (Data?, Error?) -> Void) {
        guard let connection = connection.value else {
            receiveConfirmation(nil, CommonError.unexpected("Connection is died"))
            return
        }
        connection.receiveRequest(data) { receiveConfirmation($0, $1?.xpcCompatible()) }
    }
    
    func sendReply(id: UUID, data: Data?, error: Error?) {
        connection.value?.receiveReply(id: id, response: .init(success: data, failure: error?.xpcCompatible()))
    }
}
