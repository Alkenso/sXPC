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

extension NSCoder {
    /// Encode codable type as JSON using given NSCoder
    /// - Throws: NSException named `NSInvalidArchiveOperationException` if encoding fails
    public func encodeCodable<T: Encodable>(_ value: T, forKey key: String) {
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
    
    /// Decode codable type as JSON using given NSCoder
    /// - Returns: Decoded object or nil if decoding fails
    public func decodeCodable<T: Decodable>(_ type: T.Type = T.self, forKey key: String) -> T? {
        guard let data = decodeObject(forKey: key) as? Data else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}

extension NSXPCInterface {
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
    
    /// Custom classes inherited from NSSecureCoding and nested in collections (NSDictionary, NSArray and same)
    /// must be explicitly declared for XPC runtime.
    /// The method declares custom types, adding most popular built-in types
    /// to cover potential nested classes inside custom onces.
    /// - Note: for more information on custom classes sent over XPC refer to 'Working with Custom Classes' paragraph of https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html
    public func extendClasses(_ classes: [Any], for sel: Selector, argumentIndex arg: Int, ofReply: Bool) {
        let existingClasses = self.classes(for: sel, argumentIndex: arg, ofReply: ofReply)
        let extendedClasses = existingClasses.union(Self.defaultClasses).union(NSSet(array: classes) as Set)
        setClasses(extendedClasses, for: sel, argumentIndex: arg, ofReply: ofReply)
    }
    
    public enum SelectorArgument {
        case byCopy(classes: [Any], argumentIndex: Int, ofReply: Bool)
        case byProxy(interface: NSXPCInterface, argumentIndex: Int, ofReply: Bool)
    }
    
    /// Custom classes inherited from NSSecureCoding and nested in collections (NSDictionary, NSArray and same)
    /// must be explicitly declared for XPC runtime.
    /// The method declares custom types, adding most popular built-in types
    /// to cover potential nested classes inside custom onces.
    /// - Note: This is 'object-oriented' approach of `extendClasses(_:for:argumentIndex:ofReply:`
    ///
    /// For more information on custom classes sent over XPC refer to 'Working with Custom Classes' paragraph of https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html
    public func extendSelector(_ sel: Selector, with arguments: [SelectorArgument]) {
        for arg in arguments {
            switch arg {
            case .byCopy(let classes, let index, let ofReply):
                extendClasses(classes, for: sel, argumentIndex: index, ofReply: ofReply)
            case .byProxy(let interface, let index, let ofReply):
                setInterface(interface, for: sel, argumentIndex: index, ofReply: ofReply)
            }
        }
    }
}
