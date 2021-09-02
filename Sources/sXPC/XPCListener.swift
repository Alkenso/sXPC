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


public class XPCListener<ExportedInterface, RemoteInterface>: XPCListenerProtocol {
    public init<RemoteInterfaceXPC, ExportedInterfaceXPC>(
        listener: NSXPCListener,
        exportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>,
        remoteInterface: XPCInterface<RemoteInterface, RemoteInterfaceXPC>?
    ) {
        self.listener = listener
        _createConnection = {
            XPCConnection.listenerSide(connection: $0, serverInterface: exportedInterface, clientInterface: remoteInterface)
        }
        
        _listenerDelegate.parent = self
        listener.delegate = _listenerDelegate
    }
    
    public convenience init<ExportedInterfaceXPC>(
        listener: NSXPCListener,
        exportedInterface: XPCInterface<ExportedInterface, ExportedInterfaceXPC>
    ) where RemoteInterface == Never {
        self.init(listener: listener, exportedInterface: exportedInterface, remoteInterface: Optional<XPCInterface<RemoteInterface, Never>>.none)
    }
    
    public var newConnectionHandler: ((XPCConnection<RemoteInterface, ExportedInterface>) -> Bool)?
    public var verifyConnectionHandler: ((NSXPCConnection.SecurityInfo) -> Bool)?
    
    public func resume() {
        listener.resume()
    }
    
    public func suspend() {
        listener.suspend()
    }
    
    public func invalidate() {
        listener.invalidate()
    }
    
    public let listener: NSXPCListener
    
    
    // MARK: Private
    private let _listenerDelegate: ListenerDelegate = .init()
    private let _createConnection: (NSXPCConnection) -> XPCConnection<RemoteInterface, ExportedInterface>
}

extension XPCListener {
    private class ListenerDelegate: NSObject, NSXPCListenerDelegate {
        weak var parent: XPCListener? = nil
        
        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
            guard let parent = parent else { return false }
            guard parent.verifyConnectionHandler?(newConnection.securityInfo) != false else { return false }
            return parent.newConnectionHandler?(parent._createConnection(newConnection)) ?? false
        }
    }
}

public protocol XPCListenerProtocol: AnyObject {
    associatedtype ExportedInterface
    associatedtype RemoteInterface
    
    var newConnectionHandler: ((XPCConnection<RemoteInterface, ExportedInterface>) -> Bool)? { get set }
    var verifyConnectionHandler: ((NSXPCConnection.SecurityInfo) -> Bool)? { get set }
    
    func resume()
    func suspend()
    func invalidate()
}


// MARK: - AnyXPCListener

public extension XPCListenerProtocol {
    func eraseToAnyXPCListener() -> AnyXPCListener<Self.ExportedInterface, Self.RemoteInterface> {
        AnyXPCListener(self)
    }
}

public class AnyXPCListener<ExportedInterface, RemoteInterface>: XPCListenerProtocol {
    private let _newConnectionHandler: GetSet<((XPCConnection<RemoteInterface, ExportedInterface>) -> Bool)?>
    private let _verifyConnectionHandler: GetSet<((NSXPCConnection.SecurityInfo) -> Bool)?>
    private let _resume: () -> Void
    private let _suspend: () -> Void
    private let _invalidate: () -> Void
    
    
    public init<Listener: XPCListenerProtocol>(_ listener: Listener) where Listener.ExportedInterface == ExportedInterface, Listener.RemoteInterface == RemoteInterface {
        _newConnectionHandler = GetSet(listener, \.newConnectionHandler)
        _verifyConnectionHandler = GetSet(listener, \.verifyConnectionHandler)
        _resume = listener.resume
        _suspend = listener.suspend
        _invalidate = listener.invalidate
    }
    
    public var newConnectionHandler: ((XPCConnection<RemoteInterface, ExportedInterface>) -> Bool)? {
        get { _newConnectionHandler.get() }
        set { _newConnectionHandler.set(newValue) }
    }
    
    public var verifyConnectionHandler: ((NSXPCConnection.SecurityInfo) -> Bool)? {
        get { _verifyConnectionHandler.get() }
        set { _verifyConnectionHandler.set(newValue) }
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
