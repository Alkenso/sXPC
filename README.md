## sXPC - Swift-typed wrapper around NSXPCConneciton

**sXPC** allows you to
- make NSXPCConnection to produce typed remoteObject / set typed exportedObject
- pass Swift-specific structs/enums over XPC connection (with very little additional code)
- have NSXPCIntegrace description in the single place
- hide objective-c details, using pure Swift in the App

### XPCTranport
XPCTranport included in the package, is kind of add-on to sXPC, providing message-oriented approach to XPC communication
XPCTranport introduces sort of stable connection between client and service endpoints
- built-in handshake with initial customizable payload
- built-in reconnect behaviour
- Codable types support
- Bidirectional communication

### Library family
You can also find Swift libraries for macOS / *OS development
- [SwiftConvenience](https://github.com/Alkenso/SwiftConvenience): Swift common extensions and utilities used in everyday development
- [sLaunchctl](https://github.com/Alkenso/sLaunchctl): Swift API to register and manage daemons and user-agents
- [sMock](https://github.com/Alkenso/sMock): Swift unit-test mocking framework similar to gtest/gmock

## XPC service example
_Note: full sample code resides in **Sample** folder_

#### Assume protocol `TokenService` you are going to use over XPC connection
```
public struct TokenRequest: Equatable, Codable {
    public var user: String
    public var password: String
}

public struct TokenResponse: Equatable, Codable {
    public var token: String
    public var expiration: Date
}

public protocol TokenService {
    func requestToken(_ request: TokenRequest, reply: @escaping (Result<TokenResponse, Error>) -> Void)
}
```

#### Create connection to `TokenService` and request token
```
let connection = TokenServiceXPCConnection(xpc: .service("com.alkenso.XPCService"))
connection.resume()

let proxy = connection.remoteObjectProxy { error in
    print(error)
}

let request = TokenRequest(user: "alkenso", password: "1234567_lol")
proxy.requestToken(request) {
    print($0)
}
```

#### Setup `TokenService` listener
```
// Define TokenService implementation
struct MockTokenService: TokenService { ... }

// Start listener
let listener = CreateServiceXPCListener(listener: listener)
listener.newConnectionHandler = {
    $0.exportedObject = MockTokenService()
    $0.resume()
    return true
}
listener.resume()
```

## XPCTransport example
_Note: full sample code resides in **Sample** folder_

Assume we need to achieve two pretty common, close to real-world scenarios:
1. Receiving remote notifications
2. Sending analytic events

The logic of receiving/sending is implemented in another process and we can connect it via XPC

```
// XPCService -> App
public enum RemoteNotification: Codable {
    case notify(String)
    
    // first generic parameter - approval text
    // second generic parameter - Boolean, indicating request is approved by user
    case askApproval(XPCTransportMessage<String, Bool>)
}

// App -> XPCService
public struct AnalyticEvent: Codable {
    var reason: String
    var date: Date
}
```

#### Create connection to `XPCService`
```
// create XPCTransport connection
let connection = XPCTransportConnection(xpc: .service("com.alkenso.XPCService"))

// setup incoming messages handler
connection.setReceiveMessageHandler(RemoteNotification.self) { 
    switch $0 {
        case .notify(let text):
            print("[Notifcation] \(text)")
        case .askApproval(let message):
            print("[Approval] \(message.request)")
            
            // Reply to XPCTransportMessage
            message.reply(.success(true))
        }
    }
}

// receive connection state updates (react to reconnects)
connection.stateHandler = { print("Connection state: \($0)") }

// all handlers/replies will be called on this queue
connection.queue = .main

// activate connection
connection.activate()

// send analytic event through connection
do {
    try connection.send(AnalyticEvent(reason: "Button clicked", date: Date()))
} catch {
    print("Failed to send analytic event. Error: \(error)")
}
```

#### Setup XPCTransport server
```
// create XPCTransport server
let server = XPCTransportServer(.service)

// setup incoming messages handler
server.setReceiveMessageHandler(AnalyticEvent.self) { _, event in
    print("Analytic event: \(event)")
}

// activate server
server.activate()

// ... some time later
// send notifications to all connected clients
guard let peer = server.activeConnections.first else { return }
do {
    // send simple notification
    try server.send(to: peer, message: .notify("You have new message"))
    
    // send approval request that requires reply from the client(s)
    let message = XPCTransportMessage<String, Bool>(
        request: "New sign in detected on another device. Allow it?",
        reply: { approvalResult in
            switch approvalResult {
            case .success(let approved):
                print("Approved: \(approved)")
            case .failure(let error):
                print("Approval failed: \(error)")
            }
        }
    )
    try server.send(to: peer, message: .askApproval(message))
} catch {
    print("Failed to send notification to peer. Error: \(error)")
}
```
