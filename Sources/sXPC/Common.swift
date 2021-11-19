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


/// InterfaceXPC is underlying Obj-C compatible protocol used for NSXPCConnection.
/// - note: If the file is not in the shared framework but linked to multiple targets, name it explicitly like @objc(ExplicitNameInterfaceXPC).
/// - warning: Leave it 'internal', not 'private', due to Swift-ObjC interoperability.
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

extension XPCInterface {
    public static func direct(interface: NSXPCInterface) -> XPCInterface where Interface == InterfaceXPC {
        Self(
            interface: interface,
            toXPC: { $0 },
            fromXPC: { $0 }
        )
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
        } catch let error as NSError {
            NSException(
                name: .invalidArchiveOperationException,
                reason: "code = \(error.code), domain = \(error.domain), error = \(error.description)",
                userInfo: error.userInfo
            ).raise()
        }
    }
    
    func decodeCodable<T: Decodable>(_ type: T.Type = T.self, forKey key: String = NSCoder.defaultCodablePayloadKey) -> T? {
        guard let data = decodeObject(forKey: key) as? Data else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}

public extension NSXPCInterface {
    private static let defaultClasses = NSSet(array: [
        NSArray.self,
        NSString.self,
        NSValue.self,
        NSNumber.self,
        NSData.self,
        NSDate.self,
        NSNull.self,
        NSURL.self,
        NSUUID.self,
        NSError.self,
    ]) as Set
    
    
    func extendClasses(_ classes: [Any], for sel: Selector, argumentIndex arg: Int, ofReply: Bool) {
        let existingClasses = self.classes(for: sel, argumentIndex: arg, ofReply: ofReply)
        let extendedClasses = existingClasses.union(Self.defaultClasses).union(NSSet(array: classes) as Set)
        setClasses(extendedClasses, for: sel, argumentIndex: arg, ofReply: ofReply)
    }
    
    enum SelectorArgument {
        case byCopy(classes: [Any], argumentIndex: Int, ofReply: Bool)
        case byProxy(interface: NSXPCInterface, argumentIndex: Int, ofReply: Bool)
    }
    
    func extendSelector(_ sel: Selector, with arguments: [SelectorArgument]) {
        for arg in arguments {
            switch arg {
            case let .byCopy(classes, index, ofReply):
                extendClasses(classes, for: sel, argumentIndex: index, ofReply: ofReply)
            case let .byProxy(interface, index, ofReply):
                setInterface(interface, for: sel, argumentIndex: index, ofReply: ofReply)
            }
        }
    }
}
