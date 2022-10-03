import Foundation
import sXPC

@objc
protocol DemoServiceXPC {
    func version(reply: @escaping (String) -> Void)
    func uppercaseString(_ string: String, reply: @escaping (String) -> Void)
}

@objc
protocol DemoClientXPC {
    func printLog(_ log: String)
}
