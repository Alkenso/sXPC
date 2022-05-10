@testable import sXPC

import XCTest
import SwiftConvenienceTestUtils


class XPCTransportTests: XCTestCase {
    var nativeListener: NSXPCListener!
    var server: XPCTransportServer!
    var client: XPCTransportConnection!
    
    override func setUp() {
        nativeListener = NSXPCListener.anonymous()
        server = XPCTransportServer(.listener(nativeListener))
        server.activate()
        
        client = XPCTransportConnection(xpc: .listenerEndpoint(nativeListener.endpoint))
        client.queue = .main
    }
    
    func test_connect_invalidate() throws {
        let connectedExp = expectation(description: "Client connected")
        var invalidateExp: XCTestExpectation?
        var steps: [XPCTransportConnection.ConnectionState] = []
        client.stateHandler = { connectionState in
            switch connectionState {
            case .connected:
                connectedExp.fulfill()
            case .invalidated:
                invalidateExp?.fulfill()
            default:
                break
            }
            steps.append(connectionState)
        }
        
        // Ensure the client state become 'connected' after activation
        client.activate()
        waitForExpectations()
        
        // Ensure the client state become 'invalidate' after invalidation
        invalidateExp = expectation(description: "Client invalidate")
        client.invalidate()
        waitForExpectations()
        
        // Ensure the client went through all states: from 'waiting' to 'invalidated'
        XCTAssertEqual(steps.count, XPCTransportConnection.ConnectionState.allCases.count)
        XCTAssertEqual(Set(steps), Set(XPCTransportConnection.ConnectionState.allCases))
    }
    
    func test_serverInvalidate() throws {
        let secondClient = XPCTransportConnection(xpc: .listenerEndpoint(nativeListener.endpoint))
        secondClient.queue = .main
        
        let connectedExp = expectation(description: "Client connected")
        connectedExp.expectedFulfillmentCount = 2
        var invalidateExp: XCTestExpectation?
        let stateHandler = { (connectionState: XPCTransportConnection.ConnectionState) in
            switch connectionState {
            case .connected:
                connectedExp.fulfill()
            case .invalidated:
                invalidateExp?.fulfill()
            default:
                break
            }
        }
        client.stateHandler = stateHandler
        secondClient.stateHandler = stateHandler
        
        client.activate()
        secondClient.activate()
        waitForExpectations()
        
        invalidateExp = expectation(description: "Client invalidate")
        invalidateExp?.expectedFulfillmentCount = 2
        server.invalidate()
        waitForExpectations()
    }
    
    func test_send_clientToServer() throws {
        var activePeer: UUID?
        let expOpen = expectation(description: "connectionOpened")
        server.connectionOpened = { peer in
            activePeer = peer
            expOpen.fulfill()
        }
        var expClosed: XCTestExpectation?
        server.connectionClosed = { peer in
            XCTAssertEqual(peer, activePeer)
            expClosed?.fulfill()
        }
        
        let expServerReceive = expectation(description: "receiveDataHandler")
        server.receiveDataHandler = .decode(String.self) { peer, data, reply in
            XCTAssertEqual(peer, activePeer)
            XCTAssertEqual(data, "hello from client")
            reply(.success(.encode("hello from server")))
            expServerReceive.fulfill()
        }
        client.activate()
        
        let expClientGotResponse = expectation(description: "send reply")
        client.send(.encode("hello from client"), reply: .decode(String.self) {
            XCTAssertEqual($0.success, "hello from server")
            expClientGotResponse.fulfill()
        })
        
        waitForExpectations()
        
        expClosed = expectation(description: "connectionClosed")
        client.invalidate()
        waitForExpectations()
    }
    
    func test_send_serverToClient() throws {
        let expServerReceive = expectation(description: "server receive reply")
        server.connectionOpened = { [weak server] peer in
            DispatchQueue.global().async {
                server?.send(to: peer, payload: .encode("hello from server"), reply: .decode(String.self) {
                    XCTAssertEqual($0.success, "hello from client")
                    expServerReceive.fulfill()
                })
            }
        }
        
        let expClientReceive = expectation(description: "receiveDataHandler")
        client.receiveDataHandler = .decode(String.self) { [id = client.id] peer, data, reply in
            XCTAssertEqual(peer, id)
            XCTAssertEqual(data, "hello from server")
            reply(.success(.encode("hello from client")))
            expClientReceive.fulfill()
        }
        
        client.activate()
        waitForExpectations()
    }
    
    func test_xpcReply_decode() throws {
        XPCReply.decode(String.self) { XCTAssertEqual($0.success, "qwerty") }(.encode("qwerty"))
        XPCReply.decode(String.self) { XCTAssertNotEqual($0.success, "qwerty") }(.encode("qiop"))
        XPCReply.decode(String.self) { XCTAssertNotNil($0.failure) }(.encode(123))
        XPCReply.decode(String.self) { XCTAssertNotNil($0.failure) }(.raw(Data()))
        XPCReply.decode(String.self) { XCTAssertNotNil($0.failure) }(TestError())

        let raw = try XPCPayload.encode("qwerty").data()
        XPCReply.decode(String.self) { XCTAssertEqual($0.success, "qwerty") }(.raw(raw))
    }
}
