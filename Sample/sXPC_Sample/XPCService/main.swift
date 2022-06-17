import Foundation

struct MockTokenService: TokenService {
    func requestToken(_ request: TokenRequest, reply: @escaping (Result<TokenResponse, Error>) -> Void) {
        let token = Data((request.user + request.password).utf8).base64EncodedString()
        let expiration = Date().addingTimeInterval(3600)
        let response = TokenResponse(token: token, expiration: expiration)
        
        reply(.success(response))
    }
}

let listener = TokenServiceXPCListener(xpc: .service)
listener.newConnectionHandler = {
    $0.exportedObject = MockTokenService()
    $0.resume()
    return true
}

listener.resume()

RunLoop.main.run()
