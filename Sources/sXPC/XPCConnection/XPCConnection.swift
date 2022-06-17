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
import SwiftConvenience

/// Bidirectional XPC Connection
extension XPCConnection {
    public convenience init<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        _ type: XPCConnectionInit,
        remoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>,
        exportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>
    ) {
        self.init(
            type,
            optionalRemoteInterface: remoteInterface,
            optionalExportedInterface: exportedInterface
        )
    }
    
    public convenience init(
        connection: NSXPCConnection,
        exportedObjectConversion: @escaping ((ExportedInterface) -> Any),
        proxyObjectConversion: @escaping ((Any) -> RemoteInterface)
    ) {
        self.init(
            connection: connection,
            optionalProxyObjectConversion: proxyObjectConversion,
            optionalExportedObjectConversion: exportedObjectConversion
        )
    }
}

/// Unidirectional XPC Connection - Exported object only
extension XPCConnection where RemoteInterface == Never {
    public convenience init<ExportedInterfaceXPC>(
        _ type: XPCConnectionInit,
        exportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>
    ) {
        self.init(
            type,
            optionalRemoteInterface: (XPCInterface<RemoteInterface, Never>?).none,
            optionalExportedInterface: exportedInterface
        )
    }
    
    public convenience init(
        connection: NSXPCConnection,
        exportedObjectConversion: @escaping ((ExportedInterface) -> Any)
    ) {
        self.init(
            connection: connection,
            optionalProxyObjectConversion: nil,
            optionalExportedObjectConversion: exportedObjectConversion
        )
    }
}

/// Unidirectional XPC Connection - Remote object only
extension XPCConnection where ExportedInterface == Never {
    public convenience init<RemoteInterfaceXPC>(
        _ type: XPCConnectionInit,
        remoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>
    ) {
        self.init(
            type,
            optionalRemoteInterface: remoteInterface,
            optionalExportedInterface: XPCInterface<ExportedInterface, Never>?.none
        )
    }
    
    public convenience init(
        connection: NSXPCConnection,
        proxyObjectConversion: @escaping ((Any) -> RemoteInterface)
    ) {
        self.init(
            connection: connection,
            optionalProxyObjectConversion: proxyObjectConversion,
            optionalExportedObjectConversion: nil
        )
    }
}

/// XPCConnection is Swift typesafe wrapper around NSXPCConnection
/// - Parameters
///     - RemoteInterface: type of remote interface connection deals with. May be 'Never' if connection does not expected to use remote interface
///     - ExportedInterface: type of exported interface connection deals with. May be 'Never' if connection does not expected to use exported object
open class XPCConnection<RemoteInterface, ExportedInterface>: XPCConnectionProtocol {
    public var exportedObject: ExportedInterface? {
        didSet { native.exportedObject = exportedObject.flatMap(exportedObjectConversion) }
    }
    
    public func remoteObjectProxy(withErrorHandler handler: ((Error) -> Void)?) -> RemoteInterface {
        let proxy = native.remoteObjectProxyWithErrorHandler { handler?($0) }
        return proxyObjectConversion(proxy)
    }
    
    public func synchronousRemoteObjectProxy(withErrorHandler handler: @escaping (Error) -> Void) -> RemoteInterface {
        let proxy = native.synchronousRemoteObjectProxyWithErrorHandler(handler)
        return proxyObjectConversion(proxy)
    }
    
    public var invalidationHandler: (() -> Void)? {
        get { native.invalidationHandler }
        set { native.invalidationHandler = newValue }
    }
    
    public var interruptionHandler: (() -> Void)? {
        get { native.interruptionHandler }
        set { native.interruptionHandler = newValue }
    }
    
    public func resume() {
        native.resume()
    }
    
    public func suspend() {
        native.suspend()
    }
    
    public func invalidate() {
        native.invalidate()
    }
    
    public let native: NSXPCConnection
    
    // MARK: Private
    
    private let exportedObjectConversion: (ExportedInterface) -> Any
    private let proxyObjectConversion: (Any) -> RemoteInterface
    
    private convenience init<ExportedInterfaceXPC, RemoteInterfaceXPC>(
        _ endpoint: XPCConnectionInit,
        optionalRemoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>?,
        optionalExportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>?
    ) {
        self.init(
            connection: endpoint.connection,
            optionalProxyObjectConversion: optionalRemoteInterface?.fromXPC,
            optionalExportedObjectConversion: optionalExportedInterface?.toXPC
        )
        native.exportedInterface = optionalExportedInterface?.interface
        native.remoteObjectInterface = optionalRemoteInterface?.interface
    }
    
    private init(
        connection: NSXPCConnection,
        optionalProxyObjectConversion: ((Any) -> RemoteInterface)?,
        optionalExportedObjectConversion: ((ExportedInterface) -> Any)?
    ) {
        self.native = connection
        self.exportedObjectConversion = optionalExportedObjectConversion ?? { _ in fatalError("Exported interface not set.") }
        self.proxyObjectConversion = optionalProxyObjectConversion ?? { _ in fatalError("Remote interface not set.") }
        
        registerInStorage()
    }
    
    deinit {
        underesterFromStorage()
    }
}

private var _currentConnectionStorage = Synchronized<[ObjectIdentifier: AnyObject]>(.serial)

extension XPCConnection {
    public static func current() throws -> XPCConnection {
        guard let connection = NSXPCConnection.current() else {
            throw CommonError.unwrapNil("NSXPCConnection.current")
        }
        guard let current = _currentConnectionStorage.read({ $0[ObjectIdentifier(connection)] }) else {
            throw CommonError.notFound(what: "NSXPCConnection", where: "currentConnectionStorage")
        }
        if let concreteCurrent = current as? Self {
            return concreteCurrent
        } else {
            assertionFailure("Failed to cast \(current) connection to \(Self.self)")
            throw CommonError.cast(current, to: Self.self)
        }
    }
    
    private func registerInStorage() {
        _currentConnectionStorage.writeAsync { $0[ObjectIdentifier(self.native)] = self }
    }
    
    private func underesterFromStorage() {
        _currentConnectionStorage.writeAsync { $0.removeValue(forKey: ObjectIdentifier(self.native)) }
    }
}

// MARK: - XPCConnection Auxiliary

public enum XPCConnectionInit {
    case service(_ name: String)
    case machService(_ name: String, options: NSXPCConnection.Options)
    case listenerEndpoint(_ listenerEndpoint: NSXPCListenerEndpoint)
    case connection(_ connection: NSXPCConnection)
}

extension XPCConnectionInit {
    public var connection: NSXPCConnection {
        switch self {
        case .service(let name):
            return NSXPCConnection(serviceName: name)
        case .machService(let name, let options):
            return NSXPCConnection(machServiceName: name, options: options)
        case .listenerEndpoint(let listenerEndpoint):
            return NSXPCConnection(listenerEndpoint: listenerEndpoint)
        case .connection(let connection):
            return connection
        }
    }
}

public protocol XPCConnectionProtocol: AnyObject {
    associatedtype ExportedInterface
    associatedtype RemoteInterface
    
    var exportedObject: ExportedInterface? { get set }
    
    func remoteObjectProxy(withErrorHandler handler: ((Error) -> Void)?) -> RemoteInterface
    func synchronousRemoteObjectProxy(withErrorHandler handler: @escaping (Error) -> Void) -> RemoteInterface
    
    var invalidationHandler: (() -> Void)? { get set }
    var interruptionHandler: (() -> Void)? { get set }
    
    func resume()
    func suspend()
    func invalidate()
}

extension XPCConnectionProtocol {
    public var remoteObjectProxy: RemoteInterface {
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
    private let _synchronousRemoteObjectProxy: (@escaping (Error) -> Void) -> RemoteInterface
    private let _resume: () -> Void
    private let _suspend: () -> Void
    private let _invalidate: () -> Void
    
    public init<Connection: XPCConnectionProtocol>(_ connection: Connection) where Connection.RemoteInterface == RemoteInterface, Connection.ExportedInterface == ExportedInterface {
        self._exportedObject = .init(connection, \.exportedObject)
        self._invalidationHandler = .init(connection, \.invalidationHandler)
        self._interruptionHandler = .init(connection, \.interruptionHandler)
        self._remoteObjectProxy = connection.remoteObjectProxy
        self._synchronousRemoteObjectProxy = connection.synchronousRemoteObjectProxy
        self._resume = connection.resume
        self._suspend = connection.suspend
        self._invalidate = connection.invalidate
    }
    
    public var exportedObject: ExportedInterface? {
        get { _exportedObject.get() }
        set { _exportedObject.set(newValue) }
    }
    
    public func remoteObjectProxy(withErrorHandler handler: ((Error) -> Void)?) -> RemoteInterface {
        _remoteObjectProxy(handler)
    }
    
    public func synchronousRemoteObjectProxy(withErrorHandler handler: @escaping (Error) -> Void) -> RemoteInterface {
        _synchronousRemoteObjectProxy(handler)
    }
    
    public var invalidationHandler: (() -> Void)? {
        get { _invalidationHandler.get() }
        set { _invalidationHandler.set(newValue) }
    }
    
    public var interruptionHandler: (() -> Void)? {
        get { _interruptionHandler.get() }
        set { _interruptionHandler.set(newValue) }
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
