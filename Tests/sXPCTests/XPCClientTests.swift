import sXPC

import SpellbookFoundation
import SpellbookTestUtils
import XCTest

class XPCClientTests: XCTestCase {
    private typealias Client = XPCClient<TestProtocolXPC, Never, String>
    
    fileprivate static let testVersion = "1.0.2"
    private var listener: sXPC.XPCListener<TestProtocolXPC, Never>!
    private var client: Client!
    
    override func setUp() {
        client = Client(remoteInterface: .direct(TestProtocolXPC.self))
        client.requestEndpointHandler = { [weak self] in $0(self.flatMap { .listenerEndpoint($0.listener.endpoint) }) }
        client.connectHandler = { context in
            context.remoteObjectProxy().version(reply: context.complete)
        }
        
        updateListener()
    }
    
    private func updateListener() {
        listener = XPCListener<TestProtocolXPC, Never>(.anonymous, exportedInterface: .direct(TestProtocolXPC.self))
        listener.newConnectionHandler = {
            $0.exportedObject = ExportedObject()
            $0.resume()
            return true
        }
        listener.resume()
    }
    
    func test_typical() throws {
        var subscriptions: [SubscriptionToken] = []
        
        let expStateChange = expectation(description: "Connection state changed when connected")
        client.connectedState.subscribe { state in
            if let state {
                XCTAssertEqual(state, Self.testVersion)
                expStateChange.fulfill()
            }
        }.store(in: &subscriptions)
        
        client.activate()
        waitForExpectations()
        
        let expXPCReplied = expectation(description: "Reply from call over XPC came")
        client.remoteObjectProxy().uppercaseString(from: "some string") {
            XCTAssertEqual($0, "SOME STRING")
            expXPCReplied.fulfill()
        }
        
        waitForExpectations()
    }
    
    func test_reconnect() throws {
        var subscriptions: [SubscriptionToken] = []
        
        var expStateChange = expectation(description: "Connection state changed when connected")
        client.connectedState.subscribe { state in
            if let state {
                XCTAssertEqual(state, Self.testVersion)
                expStateChange.fulfill()
            }
        }.store(in: &subscriptions)
        
        client.reconnectDelay = 0
        
        client.activate()
        waitForExpectations()
        
        expStateChange = expectation(description: "Connection state after when REconnected")
        let oldListener = listener
        updateListener()
        oldListener?.invalidate()
        
        waitForExpectations()
    }
}

@objc
private protocol TestProtocolXPC {
    func version(reply: @escaping (String) -> Void)
    func uppercaseString(from string: String, reply: @escaping (String) -> Void)
}

private class ExportedObject: NSObject, TestProtocolXPC {
    func version(reply: @escaping (String) -> Void) {
        reply(XPCClientTests.testVersion)
    }
    
    func uppercaseString(from string: String, reply: @escaping (String) -> Void) {
        reply(string.uppercased())
    }
}
