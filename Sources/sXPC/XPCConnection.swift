/*
 * MIT License
 *
 * Copyright (c) 2020 Alkenso (Vladimir Vashurkin)
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


public class XPCConnection<RemoteInterface, ExportedInterface>: XPCConnectionProtocol {
    public var exportedObject: ExportedInterface? {
        didSet { underlyingConnection.exportedObject = exportedObject.flatMap(_exportedObjectConvertion) }
    }
    
    public var invalidationHandler: (() -> Void)? {
        get { underlyingConnection.invalidationHandler }
        set { underlyingConnection.invalidationHandler = newValue }
    }
    
    public var interruptionHandler: (() -> Void)? {
        get { underlyingConnection.interruptionHandler }
        set { underlyingConnection.interruptionHandler = newValue }
    }
    
    public func remoteObjectProxy(withErrorHandler handler: ((Error) -> Void)?) -> RemoteInterface {
        let proxy = underlyingConnection.remoteObjectProxyWithErrorHandler { handler?($0) }
        return _proxyConvertion(proxy)
    }
    
    public func synchronousRemoteObjectProxy(withErrorHandler handler: @escaping (Error) -> Void) -> RemoteInterface {
        let proxy = underlyingConnection.synchronousRemoteObjectProxyWithErrorHandler(handler)
        return _proxyConvertion(proxy)
    }
    
    public func resume() {
        underlyingConnection.resume()
    }
    
    public func suspend() {
        underlyingConnection.suspend()
    }
    
    public func invalidate() {
        underlyingConnection.invalidate()
    }
    
    public let underlyingConnection: NSXPCConnection
    
    
    // MARK: Private
    private let _proxyConvertion: (Any) -> RemoteInterface
    private let _exportedObjectConvertion: (ExportedInterface) -> Any
    
    
    private init<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        connection: NSXPCConnection,
        remoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>?,
        exportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>?
    ) {
        underlyingConnection = connection
        
        if let remoteInterface = remoteInterface {
            _proxyConvertion = remoteInterface.fromXPC
            connection.remoteObjectInterface = remoteInterface.interface
        } else {
            _proxyConvertion = { _ in fatalError("Remote interface not set.") }
        }
        
        if let exportedInterface = exportedInterface {
            connection.exportedInterface = exportedInterface.interface
            _exportedObjectConvertion = { exportedInterface.toXPC($0) }
        } else {
            _exportedObjectConvertion = { _ in fatalError("Exported interface not set.") }
        }
        
        registerInStorage()
    }
    
    deinit {
        underesterFromStorage()
    }
}

private let _queue = DispatchQueue(label: "XPCConnection.currentStorage.queue")
private var _currentConnectionStorage: [ObjectIdentifier: AnyObject] = [:]

public extension XPCConnection {
    static var current: XPCConnection? {
        _queue.sync {
            guard let connection = NSXPCConnection.current() else { return nil }
            guard let current = _currentConnectionStorage[ObjectIdentifier(connection)] else { return nil }
            if let concreteCurrent = current as? Self {
                return concreteCurrent
            } else {
                assertionFailure("Failed to cast \(current) connection to \(Self.self)")
                return nil
            }
        }
    }
    
    private func registerInStorage() {
        _queue.sync {
            _currentConnectionStorage[ObjectIdentifier(underlyingConnection)] = self
        }
    }
    
    private func underesterFromStorage() {
        _queue.sync {
            _ = _currentConnectionStorage.removeValue(forKey: ObjectIdentifier(underlyingConnection))
        }
    }
}

public extension XPCConnection {
    convenience init<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        connectionSide connection: NSXPCConnection,
        serverInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>,
        clientInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>?
    ) {
        self.init(connection: connection, remoteInterface: serverInterface, exportedInterface: clientInterface)
    }
    
    static func connectionSide<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        connection: NSXPCConnection,
        serverInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>,
        clientInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>?
    ) -> XPCConnection {
        XPCConnection(connectionSide: connection, serverInterface: serverInterface, clientInterface: clientInterface)
    }
    
    convenience init<RemoteInterfaceXPC>(
        connectionSide connection: NSXPCConnection,
        serverInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>
    ) {
        self.init(connectionSide: connection, serverInterface: serverInterface, clientInterface: Optional<XPCInterface<ExportedInterface, Never>>.none)
    }
    
    static func connectionSide<RemoteInterfaceXPC>(
        connection: NSXPCConnection,
        serverInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>
    ) -> XPCConnection where ExportedInterface == Never {
        XPCConnection(connectionSide: connection, serverInterface: serverInterface)
    }
    
    
    convenience init<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        listenerSide connection: NSXPCConnection,
        serverInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>,
        clientInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>?
    ) {
        self.init(connection: connection, remoteInterface: clientInterface, exportedInterface: serverInterface)
    }
    
    static func listenerSide<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        connection: NSXPCConnection,
        serverInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>,
        clientInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>?
    ) -> XPCConnection {
        XPCConnection(listenerSide: connection, serverInterface: serverInterface, clientInterface: clientInterface)
    }
    
    convenience init<ExportedInterfaceXPC>(
        listenerSide connection: NSXPCConnection,
        serverInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>
    ) {
        self.init(listenerSide: connection, serverInterface: serverInterface, clientInterface: Optional<XPCInterface<RemoteInterface, Never>>.none)
    }
    
    static func listenerSide<ExportedInterfaceXPC>(
        connection: NSXPCConnection,
        serverInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>
    ) -> XPCConnection where RemoteInterface == Never {
        XPCConnection(listenerSide: connection, serverInterface: serverInterface)
    }
}

public protocol XPCConnectionProtocol: AnyObject {
    associatedtype RemoteInterface
    associatedtype ExportedInterface
    
    var exportedObject: ExportedInterface? { get set }
    var invalidationHandler: (() -> Void)? { get set }
    var interruptionHandler: (() -> Void)? { get set }
    
    func remoteObjectProxy(withErrorHandler handler: ((Error) -> Void)?) -> RemoteInterface
    func synchronousRemoteObjectProxy(withErrorHandler handler: @escaping (Error) -> Void) -> RemoteInterface
    func resume()
    func suspend()
    func invalidate()
}

public extension XPCConnectionProtocol {
    var remoteObjectProxy: RemoteInterface {
        remoteObjectProxy(withErrorHandler: nil)
    }
}


// MARK: - AnyXPCConnection

public extension XPCConnectionProtocol {
    func eraseToAnyXPCConnection() -> AnyXPCConnection<Self.RemoteInterface, Self.ExportedInterface> {
        AnyXPCConnection(self)
    }
}

public class AnyXPCConnection<RemoteInterface, ExportedInterface>: XPCConnectionProtocol {
    private let _exportedObject: GetSet<ExportedInterface?>
    private let _invalidationHandler: GetSet<(() -> Void)?>
    private let _interruptionHandler: GetSet<(() -> Void)?>
    private let _remoteObjectProxy: (((Error) -> Void)?) -> RemoteInterface
    private let _synchronousRemoteObjectProxy: ((@escaping (Error) -> Void) -> RemoteInterface)
    private let _resume: () -> Void
    private let _suspend: () -> Void
    private let _invalidate: () -> Void
    
    
    public init<Connection: XPCConnectionProtocol>(_ connection: Connection) where Connection.RemoteInterface == RemoteInterface, Connection.ExportedInterface == ExportedInterface {
        _exportedObject = .init(connection, \.exportedObject)
        _invalidationHandler = .init(connection, \.invalidationHandler)
        _interruptionHandler = .init(connection, \.interruptionHandler)
        _remoteObjectProxy = connection.remoteObjectProxy
        _synchronousRemoteObjectProxy = connection.synchronousRemoteObjectProxy
        _resume = connection.resume
        _suspend = connection.suspend
        _invalidate = connection.invalidate
    }
    
    public var exportedObject: ExportedInterface? {
        get { _exportedObject.get() }
        set { _exportedObject.set(newValue) }
    }
    
    public var invalidationHandler: (() -> Void)? {
        get { _invalidationHandler.get() }
        set { _invalidationHandler.set(newValue) }
    }
    
    public var interruptionHandler: (() -> Void)? {
        get { _interruptionHandler.get() }
        set { _interruptionHandler.set(newValue) }
    }
    
    public func remoteObjectProxy(withErrorHandler handler: ((Error) -> Void)?) -> RemoteInterface {
        _remoteObjectProxy(handler)
    }
    
    public func synchronousRemoteObjectProxy(withErrorHandler handler: @escaping (Error) -> Void) -> RemoteInterface {
        _synchronousRemoteObjectProxy(handler)
    }
    
    public func resume() {
        _resume()
    }
    
    public func suspend() {
        _suspend()
    }
    
    public func invalidate() {
        _invalidate()
    }
}
