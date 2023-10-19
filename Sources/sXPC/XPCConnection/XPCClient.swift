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

/// XPCClient is a wrapper around XPCConnection that provide KeepAlive ability for the connection.
public class XPCClient<RemoteInterface, ExportedInterface, ConnectedState> {
    private typealias Connection = XPCConnection<RemoteInterface, ExportedInterface>
    
    private let connectedStateStore: ValueStore<ConnectedState?>
    private let queue: DispatchQueue
    private var connection: Connection
    private let createConnection: (XPCConnectionInit) -> Connection
    
    /// When connection should be (re)created, the handler is called to provide fresh endpoint to connect.
    /// - Parameter callback: Callback handler called with fresh endpoint to connect.
    ///                       Passing `nil` means another reconnect attempt should be made.
    /// - Warning: Mandatory handler. If not set, whole client may behave oddy.
    ///
    /// - Note: You are able to call `invalidate` on the client to stop reconnect attempts.
    public var requestEndpointHandler: ((@escaping (XPCConnectionInit?) -> Void) -> Void)?
    
    /// When connection is (re)connected, client calls this handler to trigger XPC connection to be established.
    /// Because of on-demand nature of XPC, at least one XPC remote procedure call should be made to
    /// actually start the communication.
    /// - Parameter context: `ConnectContext` structure to perform custom connect routines.
    /// - Warning: Mandatory handler. If not set, whole client may behave oddy.
    public var connectHandler: ((ConnectContext) -> Void)?
    
    /// An exported object for the connection. Messages sent to the remoteObjectProxy
    /// from the other side of the connection will be dispatched to this object.
    ///
    /// When connection is (re)connected, client calls this handler
    /// to get fresh XPC exported object for the connection.
    /// - returns: exported object used for XPC connection.
    /// - Warning: If `ExportedInterface` is `Void` or `Never`, leave it as is (`nil`).
    ///            Otherwise, if not set, whole client may behave oddy.
    public var exportedObject: (() -> ExportedInterface)?
    
    /// Perform connection invalidation if connection interrups occur.
    /// Usually you want to have this `true` because on client side there is no way
    /// to distinguish service process death from service-side connection invalidation or exact XPC call failure.
    public var invalidateOnInterrupt = true
    
    /// Delay between connection invalidation and next reconnect attempt.
    public var reconnectDelay: TimeInterval = 1.0
    
    /// Observalbe state of the connection. The value is present when connection is alive.
    /// Can be used to monitor connection state (connected/not connected).
    public let connectedState: Observable<ConnectedState?>
    
    // Get a proxy for the remote object (that is, the object exported from the other side of this connection).
    public func remoteObjectProxy(synchronous: Bool = false, errorHandler: ((Error) -> Void)? = nil) -> RemoteInterface {
        connection.remoteObjectProxy(synchronous: synchronous, errorHandler: errorHandler)
    }
    
    /// Activate XPCClient, causing first connection attempt to be made.
    ///
    /// You can observe the connection state through `connectedState` observable property.
    public func activate() {
        assert(requestEndpointHandler != nil, "requestEndpointHandler MUST be set")
        assert(connectHandler != nil, "connectHandler MUST be set")
        if !(ExportedInterface.self == Never.self || ExportedInterface.self == Void.self) {
            assert(exportedObject != nil, "exportedObject MUST be set")
        }
        
        reconnect(dropState: false, immediately: true)
    }
    
    /// Invalidate XPCClient and underlying connection. All futher calls to proxy objects will fail.
    /// The client would not reconnect anymore.
    public func invalidate() {
        queue.async { [self] in
            requestEndpointHandler = nil
            connection.invalidate()
        }
    }
    
    private init<ExportedInterfaceXPC, RemoteInterfaceXPC>(
        remoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>,
        optionalExportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>?
    ) {
        let createConnection = {
            Connection(
                $0,
                optionalRemoteInterface: remoteInterface,
                optionalExportedInterface: optionalExportedInterface
            )
        }
        let infoStore = ValueStore<ConnectedState?>(initialValue: nil)
        
        self.queue = DispatchQueue(label: "\(Self.self).queue")
        self.connectedStateStore = infoStore
        self.connectedState = infoStore.asObservable
        self.connection = createConnection(.connection(.init(serviceName: "not activated connection")))
        self.createConnection = createConnection
    }
    
    private func prepareAndConnect(to connection: Connection) {
        dispatchPrecondition(condition: .onQueue(queue))
        
        // Prepare Connection
        connection.exportedObject = exportedObject?()
        connection.interruptionHandler = { [invalidateOnInterrupt, weak connection] in
            guard invalidateOnInterrupt else { return }
            connection?.invalidate()
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            connection?.invalidationHandler = nil
            self?.reconnect()
        }
        
        // Resume it
        connection.resume()
        
        // Perform custom connect
        let context = ConnectContext(
            remoteObjectProxyFn: {
                connection.remoteObjectProxy(synchronous: $0)
            },
            completeFn: {
                if let state = $0 {
                    self.connectedStateStore.update(state)
                } else {
                    connection.invalidate()
                }
            }
        )
        connectHandler?(context)
    }
    
    private func reconnect(dropState: Bool = true, immediately: Bool = false) {
        queue.async { [self] in
            if dropState {
                connectedStateStore.update(nil)
            }
            
            guard let requestEndpointHandler else { return }
            
            queue.asyncAfter(deadline: .now() + (immediately ? 0 : reconnectDelay)) {
                requestEndpointHandler { [weak self] endpoint in
                    guard let self = self else { return }
                    if let endpoint {
                        self.connection = self.createConnection(endpoint)
                        self.prepareAndConnect(to: self.connection)
                    } else {
                        self.reconnect(dropState: false, immediately: false)
                    }
                }
            }
        }
    }
}

extension XPCClient {
    /// Bidirectional XPC Client.
    public convenience init<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        remoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>,
        exportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>
    ) {
        self.init(
            remoteInterface: remoteInterface,
            optionalExportedInterface: exportedInterface
        )
    }
}

extension XPCClient where ExportedInterface == Never {
    /// Unidirectional XPC Client - Remote object only.
    public convenience init<RemoteInterfaceXPC>(remoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>) {
        self.init(
            remoteInterface: remoteInterface,
            optionalExportedInterface: XPCInterface<ExportedInterface, Never>?.none
        )
    }
}

extension XPCClient {
    /// Connection context used for custom connection routine.
    public struct ConnectContext {
        internal var remoteObjectProxyFn: (_ synchronous: Bool) -> RemoteInterface
        internal var completeFn: (ConnectedState?) -> Void
    }
}

extension XPCClient.ConnectContext {
    /// Obtain the remote proxy object of currently establishing connection.
    /// Use the proxy to perform custom connect to the service.
    ///
    /// - Note: as custom connect you can use simple methods like `ping(reply: @escaping () -> Void)` or
    ///         `version(reply: @escaping (String) -> Void).`
    ///
    /// - Warning: Do NOT own proxy object returned from this method, use `remoteObjectProxy(...)` method
    ///            from XPCClient when connected.
    public func remoteObjectProxy(synchronous: Bool = false) -> RemoteInterface {
        remoteObjectProxyFn(synchronous)
    }
    
    /// Marks the connection as completed. Pass state object is connection is successfull or `nil` to invalidate
    /// current connection and trigger next reconnect attempt.
    ///
    /// Should be called exactly once.
    public func complete(_ state: ConnectedState?) {
        completeFn(state)
    }
    
    /// Marks the connection as completed.
    ///
    /// Should be called exactly once.
    public func complete() where ConnectedState == Void {
        complete(())
    }
}
