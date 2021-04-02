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


public struct XPCInterface<Interface, InterfaceXPC> {
    public let interface: NSXPCInterface
    let toXPC: (Interface) -> InterfaceXPC
    let fromXPC: (Any) -> Interface
    
    public init(interface: NSXPCInterface, toXPC: @escaping (Interface) -> InterfaceXPC, fromXPC: @escaping (InterfaceXPC) -> Interface) {
        self.interface = interface
        self.toXPC = toXPC
        self.fromXPC = {
            guard let proxy = $0 as? InterfaceXPC else {
                fatalError("Proxy MUST be of type \(InterfaceXPC.self).")
            }
            return fromXPC(proxy)
        }
    }
}

public extension NSXPCConnection {
    struct SecurityInfo {
        public let auditToken: audit_token_t
        public let auditSessionIdentifier: au_asid_t
        public let processIdentifier: pid_t
        public let effectiveUserIdentifier: uid_t
        public let effectiveGroupIdentifier: gid_t
    }
    
    var securityInfo: SecurityInfo {
        SecurityInfo(
            auditToken: privateAuditToken,
            auditSessionIdentifier: auditSessionIdentifier,
            processIdentifier: processIdentifier,
            effectiveUserIdentifier: effectiveUserIdentifier,
            effectiveGroupIdentifier: effectiveGroupIdentifier
        )
    }
    
    private var privateAuditToken: audit_token_t {
        unsafeBitCast(value(forKey: "auditToken").unsafelyUnwrapped, to: audit_token_t.self)
    }
}

public extension NSCoder {
    static let defaultCodablePayloadKey = "payload"
    
    func encodeCodable<T: Encodable>(_ value: T, forKey key: String = NSCoder.defaultCodablePayloadKey) {
        do {
            let data = try JSONEncoder().encode(value)
            encode(data, forKey: key)
        } catch {
            failWithError(error)
        }
    }
    
    func decodeCodable<T: Decodable>(ofType type: T.Type = T.self, forKey key: String = NSCoder.defaultCodablePayloadKey) -> T? {
        guard let data = decodeObject(forKey: key) as? Data else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            failWithError(error)
            return nil
        }
    }
}
