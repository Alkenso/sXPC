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
        var steps: [XPCTransportConnectionState] = []
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
        XCTAssertEqual(steps.count, XPCTransportConnectionState.allCases.count)
        XCTAssertEqual(Set(steps), Set(XPCTransportConnectionState.allCases))
    }
    
    func test_serverInvalidate() throws {
        let secondClient = XPCTransportConnection(xpc: .listenerEndpoint(nativeListener.endpoint))
        secondClient.queue = .main
        
        let connectedExp = expectation(description: "Client connected")
        connectedExp.expectedFulfillmentCount = 2
        var invalidateExp: XCTestExpectation?
        let stateHandler = { (connectionState: XPCTransportConnectionState) in
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
        typealias Message = XPCTransportMessage<String, String>
        
        let activePeer = client.peerID
        let peerUserInfo = Data(pod: 100500)
        client.peerUserInfo = peerUserInfo
        
        let expOpen = expectation(description: "connectionOpened")
        server.connectionOpened = { peer in
            XCTAssertEqual(peer.id, activePeer)
            XCTAssertEqual(peer.userInfo, peerUserInfo)
            expOpen.fulfill()
        }
        var expClosed: XCTestExpectation?
        server.connectionClosed = { peer in
            XCTAssertEqual(peer.id, activePeer)
            XCTAssertEqual(peer.userInfo, peerUserInfo)
            expClosed?.fulfill()
        }
        
        let expServerReceive = expectation(description: "receiveMessageHandler")
        server.setReceiveMessageHandler(Message.self) { peer, message in
            XCTAssertEqual(peer.id, activePeer)
            XCTAssertEqual(peer.userInfo, peerUserInfo)
            XCTAssertEqual(message.request, "hello from client")
            message.reply(.success("hello from server"))
            expServerReceive.fulfill()
        }
        
        client.activate()
        
        let expClientGotResponse = expectation(description: "send reply")
        try client.send(Message(request: "hello from client", reply: {
            XCTAssertEqual($0.success, "hello from server")
            expClientGotResponse.fulfill()
        }))
        
        waitForExpectations()
        
        expClosed = expectation(description: "connectionClosed")
        client.invalidate()
        waitForExpectations()
    }
    
    func test_send_serverToClient() throws {
        typealias Message = XPCTransportMessage<String, String>
        
        let expServerReceive = expectation(description: "server receive reply")
        server.connectionOpened = { [weak server] peer in
            DispatchQueue.global().async {
                do {
                    try server.get().send(to: peer.id, message: Message(request: "hello from server", reply: {
                        XCTAssertEqual($0.success, "hello from client")
                        expServerReceive.fulfill()
                    }))
                } catch {
                    XCTFail("Failed to send message to \(peer). Error: \(error)")
                }
            }
        }
        
        let expClientReceive = expectation(description: "receiveMessageHandler")
        client.setReceiveMessageHandler(Message.self) {
            XCTAssertEqual($0.request, "hello from server")
            $0.reply(.success("hello from client"))
            expClientReceive.fulfill()
        }
        
        client.activate()
        waitForExpectations()
    }
    
    func test_xpcvoid() throws {
        typealias Message = XPCTransportMessage<XPCVoid, XPCVoid>
        
        let expOpen = expectation(description: "connectionOpened")
        server.connectionOpened = { _ in expOpen.fulfill() }
        
        let expServerReceive = expectation(description: "receiveMessageHandler")
        server.setReceiveMessageHandler(Message.self) { peer, message in
            message.reply(.success(.init()))
            expServerReceive.fulfill()
        }
        
        client.activate()
        
        let expClientGotResponse = expectation(description: "send reply")
        try client.send(Message {
            XCTAssertNil($0.failure)
            expClientGotResponse.fulfill()
        })
        
        waitForExpectations()
    }
}
