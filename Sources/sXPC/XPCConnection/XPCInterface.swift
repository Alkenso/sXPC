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
    /// Creates `XPCInterface` instance for case when exposed and internal interfaces are the same.
    public static func direct(_ interface: NSXPCInterface) -> XPCInterface where Interface == InterfaceXPC {
        Self(
            interface: interface,
            toXPC: { $0 },
            fromXPC: { $0 }
        )
    }
    
    /// Creates `XPCInterface` instance for case when exposed and internal interfaces are the same.
    public static func direct(_ protocol: Protocol) -> XPCInterface where Interface == InterfaceXPC {
        .direct(NSXPCInterface(with: `protocol`))
    }
}
