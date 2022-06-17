import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let connection = TokenServiceXPCConnection(xpc: .service("com.alkenso.XPCService"))
        connection.resume()
        
        let proxy = connection.remoteObjectProxy { error in
            print(error)
        }
        
        let request = TokenRequest(user: "alkenso", password: "1234567_lol")
        proxy.requestToken(request) {
            print($0)
        }
    }
}
