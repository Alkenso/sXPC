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
import SpellbookFoundation

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

/// XPCConnection is Swift typesafe wrapper around NSXPCConnection.
/// - Parameters
///     - RemoteInterface: type of remote interface connection deals with.
///       May be 'Never' if connection does not expected to use remote interface.
///     - ExportedInterface: type of exported interface connection deals with.
///       May be 'Never' if connection does not expected to use exported object.
open class XPCConnection<RemoteInterface, ExportedInterface> {
    public var exportedObject: ExportedInterface? {
        didSet { native.exportedObject = exportedObject.flatMap(exportedObjectConversion) }
    }
    
    public func remoteObjectProxy(synchronous: Bool = false, errorHandler: ((Error) -> Void)? = nil) -> RemoteInterface {
        let proxy: Any
        if synchronous {
            proxy = native.synchronousRemoteObjectProxyWithErrorHandler { errorHandler?($0)}
        } else {
            proxy = native.remoteObjectProxyWithErrorHandler { errorHandler?($0)}
        }
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
    
    internal convenience init<ExportedInterfaceXPC, RemoteInterfaceXPC>(
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
        unregisterFromStorage()
    }
}

private let _currentConnectionStorage = Synchronized<[ObjectIdentifier: Weak<AnyObject>]>(.serial)

extension XPCConnection {
    public static func current() throws -> XPCConnection {
        guard let connection = NSXPCConnection.current() else {
            throw CommonError.unwrapNil("NSXPCConnection.current")
        }
        guard let current = _currentConnectionStorage.read({ $0[ObjectIdentifier(connection)]?.value }) else {
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
        _currentConnectionStorage.writeAsync { $0[ObjectIdentifier(self.native)] = Weak(self) }
    }
    
    private func unregisterFromStorage() {
        _currentConnectionStorage.writeAsync { [id = ObjectIdentifier(native)] in $0.removeValue(forKey: id) }
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
