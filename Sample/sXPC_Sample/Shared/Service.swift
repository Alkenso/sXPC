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

public func CreateServiceXPCConnection(connection: NSXPCConnection) -> XPCConnection<Service, Never> {
    .connectionSide(connection: connection, serverInterface: CreateServiceXPCInterface())
}

public func CreateServiceXPCListener(listener: NSXPCListener) -> XPCListener<Service, Never> {
    .init(listener: listener, exportedInterface: CreateServiceXPCInterface())
}


// MARK: - AuthorizationProvider XPC support

@objc(ServiceXPC)
protocol ServiceXPC {
    func perform(_ request: Request.XPC, reply: @escaping (Response.XPC) -> Void)
}

private func CreateServiceXPCInterface() -> XPCInterface<Service, ServiceXPC> {
    class ToXPC: NSObject, ServiceXPC {
        let instance: Service
        init(_ instance: Service) { self.instance = instance }
        func perform(_ request: Request.XPC, reply: @escaping (Response.XPC) -> Void) {
            instance.perform(request.value, reply: { reply($0.xpcValue) })
        }
    }

    struct FromXPC: Service {
        let proxy: ServiceXPC
        func perform(_ request: Request, reply: @escaping (Response) -> Void) {
            proxy.perform(request.xpcValue, reply: { reply($0.value) })
        }
    }

    let interface = NSXPCInterface(with: ServiceXPC.self)
    interface.extendSelector(#selector(ServiceXPC.perform(_:reply:)), with: [
        .byCopy(classes: [Request.XPC.self], argumentIndex: 0, ofReply: false),
        .byCopy(classes: [Response.XPC.self], argumentIndex: 0, ofReply: true),
    ])

    return XPCInterface(interface: interface, toXPC: ToXPC.init, fromXPC: FromXPC.init)
}


// MARK: XPC Request

extension Request {
    typealias XPC = RequestXPC
    var xpcValue: XPC { XPC(value: self) }
}

@objc(RequestXPC)
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

@objc(ResponseXPC)
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
