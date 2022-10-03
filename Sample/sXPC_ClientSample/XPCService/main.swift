import Foundation
import sXPC

class DemoService: NSObject, DemoServiceXPC {
    private let client: DemoClientXPC
    
    init(client: DemoClientXPC) {
        self.client = client
    }
    
    func version(reply: @escaping (String) -> Void) {
        reply("0.0.1")
    }
    
    func uppercaseString(_ string: String, reply: @escaping (String) -> Void) {
        reply(string.uppercased())
        client.printLog("Requested to uppercase string \"\(string)\"")
    }
}

let listener = XPCListener<DemoServiceXPC, DemoClientXPC>(
    .service,
    exportedInterface: .direct(DemoServiceXPC.self),
    remoteInterface: .direct(DemoClientXPC.self)
)
listener.newConnectionHandler = {
    $0.exportedObject = DemoService(client: $0.remoteObjectProxy())
    $0.resume()
    return true
}

listener.resume()

RunLoop.main.run()
