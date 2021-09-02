//
//  Service.swift
//  Shared
//
//  Created by testm1 on 02.04.2021.
//

import Foundation
import sXPC


public struct Request: Equatable, Codable {
    public var processUID: uid_t
    public var processPID: pid_t
    public var processPath: URL
    
    public init(processUID: uid_t, processPID: pid_t, processPath: URL) {
        self.processUID = processUID
        self.processPID = processPID
        self.processPath = processPath
    }
}

public struct Response: Equatable, Codable {
    public var allow: Bool
    public var cache: Bool
    
    public init(allow: Bool, cache: Bool) {
        self.allow = allow
        self.cache = cache
    }
}

public protocol Service {
    func perform(_ request: Request, reply: @escaping (Response) -> Void)
}


// MARK: - Service + XPC

public typealias SampleXPCConnection = XPCConnection<Service, Never>
public extension SampleXPCConnection {
    convenience init(conneciton: NSXPCConnection) {
        self.init(connectionSide: conneciton, serverInterface: .service)
    }
}

public typealias SampleXPCListener = XPCListener<Service, Never>
public extension SampleXPCListener {
    convenience init(listener: NSXPCListener) {
        self.init(listener: listener, exportedInterface: .service)
    }
}


// MARK: - AuthorizationProvider XPC support

/// Underlying Obj-C compatible protocol used for NSXPCConnection.
/// - note: If the file is not in the shared framework but linked to multiple targets, name it explicitly like @objc(CCServiceXPC).
/// - warning: Leave it 'internal', not 'private', due to Swift-ObjC interoperability.
@objc
protocol ServiceXPC {
    func perform(_ request: Request.XPC, reply: @escaping (Response.XPC) -> Void)
}

private extension XPCInterface {
    static var service: XPCInterface<Service, ServiceXPC> {
        let interface = NSXPCInterface(with: ServiceXPC.self)
        interface.extendSelector(#selector(ServiceXPC.perform(_:reply:)), with: [
            .byCopy(classes: [Request.XPC.self], argumentIndex: 0, ofReply: false),
            .byCopy(classes: [Response.XPC.self], argumentIndex: 0, ofReply: true),
        ])

        return .init(interface: interface, toXPC: ServiceToXPC.init, fromXPC: ServiceFromXPC.init)
    }
}

private  class ServiceToXPC: NSObject, ServiceXPC {
    let instance: Service
    init(_ instance: Service) { self.instance = instance }
    func perform(_ request: Request.XPC, reply: @escaping (Response.XPC) -> Void) {
        instance.perform(request.value, reply: { reply($0.xpcValue) })
    }
}

private struct ServiceFromXPC: Service {
    let proxy: ServiceXPC
    func perform(_ request: Request, reply: @escaping (Response) -> Void) {
        proxy.perform(request.xpcValue, reply: { reply($0.value) })
    }
}


// MARK: XPC Request

extension Request {
    typealias XPC = RequestXPC
    var xpcValue: XPC { XPC(value: self) }
}

/// Underlying Obj-C compatible class backed up 'Request' type NSXPCConnection.
/// - note: If the file is not in the shared framework but linked to multiple targets, name it explicitly like @objc(CCRequestXPC).
class RequestXPC: NSObject, NSSecureCoding {
    typealias Wrapped = Request
    let value: Wrapped


    required init(value: Wrapped) {
        self.value = value
        super.init()
    }

    static var supportsSecureCoding: Bool = true

    func encode(with coder: NSCoder) {
        coder.encodeCodable(value)
    }

    required convenience init?(coder: NSCoder) {
        guard let value = coder.decodeCodable() as Wrapped? else { return nil }
        self.init(value: value)
    }
}


// MARK: XPC Response

extension Response {
    typealias XPC = ResponseXPC
    var xpcValue: XPC { XPC(value: self) }
}

class ResponseXPC: NSObject, NSSecureCoding {
    typealias Wrapped = Response
    let value: Wrapped


    required init(value: Wrapped) {
        self.value = value
        super.init()
    }

    static var supportsSecureCoding: Bool = true

    func encode(with coder: NSCoder) {
        coder.encodeCodable(value)
    }

    required convenience init?(coder: NSCoder) {
        guard let value = coder.decodeCodable() as Wrapped? else { return nil }
        self.init(value: value)
    }
}
