import Foundation
import sXPC

// MARK: TokenService public routines

public struct TokenRequest: Equatable, Codable {
    public var user: String
    public var password: String
    
    public init(user: String, password: String) {
        self.user = user
        self.password = password
    }
}

public struct TokenResponse: Equatable, Codable {
    public var token: String
    public var expiration: Date
    
    public init(token: String, expiration: Date) {
        self.token = token
        self.expiration = expiration
    }
}

public protocol TokenService {
    func requestToken(_ request: TokenRequest, reply: @escaping (Result<TokenResponse, Error>) -> Void)
}

// MARK: Service + XPC

public typealias TokenServiceXPCConnection = XPCConnection<TokenService, Never>
public extension TokenServiceXPCConnection {
    convenience init(xpc: XPCConnectionInit) {
        self.init(xpc, remoteInterface: .service)
    }
}

public typealias TokenServiceXPCListener = XPCListener<TokenService, Never>
public extension TokenServiceXPCListener {
    convenience init(xpc: XPCListenerInit) {
        self.init(xpc, exportedInterface: .service)
    }
}


// MARK: - TokenService implementation internals

/// Underlying Obj-C compatible protocol used for NSXPCConnection.
/// - note: If the file is not in the shared framework but linked to multiple targets, name it explicitly like @objc(CCServiceXPC).
/// - warning: Leave it 'internal', not 'private', due to Swift-ObjC interoperability.
@objc(TokenServiceXPC) // important thing: obj-c protocol name should be the same on both sides of the connection
protocol TokenServiceXPC {
    func requestToken(_ request: Data, reply: @escaping (Data?, Error?) -> Void)
}

private extension XPCInterface {
    static var service: XPCInterface<TokenService, TokenServiceXPC> {
        let interface = NSXPCInterface(with: TokenServiceXPC.self)
        return .init(interface: interface, toXPC: ServiceToXPC.init, fromXPC: ServiceFromXPC.init)
    }
}

private class ServiceToXPC: NSObject, TokenServiceXPC {
    let instance: TokenService
    init(_ instance: TokenService) { self.instance = instance }
    func requestToken(_ request: Data, reply: @escaping (Data?, Error?) -> Void) {
        do {
            let decoded = try JSONDecoder().decode(TokenRequest.self, from: request)
            instance.requestToken(decoded) {
                let result = $0.flatMap { response in Result { try JSONEncoder().encode(response) } }
                reply(result.success, result.failure)
            }
        } catch {
            reply(nil, error)
        }
    }
}

private struct ServiceFromXPC: TokenService {
    let proxy: TokenServiceXPC
    func requestToken(_ request: TokenRequest, reply: @escaping (Result<TokenResponse, Error>) -> Void) {
        do {
            let encoded = try JSONEncoder().encode(request)
            proxy.requestToken(encoded) {
                let response = Result(success: $0, failure: $1)
                    .flatMap { data in Result { try JSONDecoder().decode(TokenResponse.self, from: data) } }
                reply(response)
            }
        } catch {
            reply(.failure(error))
        }
    }
}
