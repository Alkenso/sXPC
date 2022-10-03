import Cocoa
import sXPC
import SwiftConvenience

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!
    private var client: XPCClient<DemoServiceXPC, DemoClientXPC, String>!
    private var subsciptions: [SubscriptionToken] = []
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        client = XPCClient(
            remoteInterface: .direct(DemoServiceXPC.self),
            exportedInterface: .direct(DemoClientXPC.self)
        )
        client.requestEndpointHandler = { $0(.service("com.alkenso.XPCService")) }
        client.connectHandler = { context in
            context.remoteObjectProxy().version {
                context.complete($0)
            }
        }
        client.exportedObject = { ExportedObject() }
        
        client.connectedState.subscribe { [weak self] in
            guard let version = $0 else { return }
            self?.handleConnectionActivated(version: version)
        }.store(in: &subsciptions)
        
        client.activate()
    }
    
    private func handleConnectionActivated(version: String) {
        print("Connected. XPC Service version = \(version)")
        
        client.remoteObjectProxy().uppercaseString("the string") { uppercased in
            print(uppercased)
        }
    }
}

private class ExportedObject: NSObject, DemoClientXPC {
    func printLog(_ log: String) {
        print("[XPC Service] \(log)")
    }
}
