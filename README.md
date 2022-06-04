## sXPC - Swift-typed wrapper around NSXPCConneciton.

sXPC allows you to
- make NSXPCConnection to produce typed remoteObject / set typed exportedObject
- pass Swift-specific structs/enums over XPC connection (with very little additional code)
- have NSXPCIntegrace description in the single place
- hide objective-c details, using pure Swift in the App

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
