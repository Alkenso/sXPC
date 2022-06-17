import Foundation
import sXPC

func scheduleNextNotification(server: XPCTransportServer) {
    DispatchQueue.global().asyncAfter(deadline: .now() + .random(in: 1 ... 3)) {
        // Generate random notification
        let notification: RemoteNotification
        if Bool.random() {
            notification = .notify("You have new message")
        } else {
            let message = XPCTransportMessage<String, Bool>(
                request: "New sign in detected on another device. Allow it?",
                reply: { approveResult in
                    switch approveResult {
                    case .success(let approved):
                        print("Approved: \(approved)")
                    case .failure(let error):
                        print("Approval failed: \(error)")
                    }
                }
            )
            notification = .askApproval(message)
        }
        
        // Send notification to all connected peers
        for peer in server.activeConnections {
            do {
                try server.send(to: peer, message: notification)
            } catch {
                print("Failed to send notification to peer. Error: \(error)")
            }
        }
        
        scheduleNextNotification(server: server)
    }
}

let server = XPCTransportServer(.service)
server.setReceiveMessageHandler(AnalyticEvent.self) { _, event in
    print("Analytic event is sent to the server. Event: \(event)")
}

scheduleNextNotification(server: server)

server.activate()
RunLoop.main.run()
