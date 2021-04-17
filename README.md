## sXPC - Swift-typed wrapper around NSXPCConneciton.

sXPC allows you to
- make NSXPCConnection to produce typed remoteObject / set typed exportedObject
- pass Swift-only structs/enums over XPC connection (with very little additional code)
- have NSXPCIntegrace description in the single place
- hide objective-c details, using pure Swift in the App

### Library family
You can also find Swift libraries for macOS / *OS development
- [SwiftConvenience](https://github.com/Alkenso/SwiftConvenience): Swift common extensions and utilities used in everyday development
- [sLaunchctl](https://github.com/Alkenso/sLaunchctl): Swift API to register and manage daemons and user-agents
- [sMock](https://github.com/Alkenso/sMock): Swift unit-test mocking framework similar to gtest/gmock

## XPC service example
_Note: full sample code resides in **Sample** folder_

#### Assume protocol you are going to use over XPC connection
```
public struct Request: Equatable, Codable {
    public var processUID: uid_t
    public var processPID: pid_t
    public var processPath: URL
}

public struct Response: Equatable, Codable {
    public var allow: Bool
    public var cache: Bool
}

public protocol Service {
    func perform(_ request: Request, reply: @escaping (Response) -> Void)
}
```

#### Create connection & call
```
let connection = CreateServiceXPCConnection(connection: NSXPCConnection(serviceName: "com.example.XPCService"))
connection.resume()

let proxy = connection.remoteObjectProxy { error in
    print(error)
}

let request = Request(...)
proxy.perform(request) { response in print(response) }
```

#### Setup listener

```
let listener = CreateServiceXPCListener(listener: listener)
listener.newConnectionHandler = {
    $0.exportedObject = DummyService()
    $0.resume()
    return true
}
listener.resume()
```
