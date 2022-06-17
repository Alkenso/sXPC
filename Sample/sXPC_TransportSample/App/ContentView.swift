import Combine
import SwiftUI
import sXPC

struct ContentView: View {
    private let connection = XPCTransportConnection(xpc: .service("com.alkenso.XPCService"))
    @State private var logEvents: [String] = []
    
    var body: some View {
        HStack(alignment: .top) {
            VStack {
                Button(action: {
                    // receive incoming messages
                    connection.setReceiveMessageHandler(RemoteNotification.self) { handleNotification($0) }
                    
                    // receive state updates
                    connection.stateHandler = { logEvents.append("Connection state: \($0)") }
                    
                    // receive all messages on main queue
                    connection.queue = .main
                    
                    // activate connection
                    connection.activate()
                }) {
                    Text("Activate")
                        .frame(maxWidth: .infinity)
                }
                .disabled(connection.state != nil)
                Divider()
                Text("Analitic events:")
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Button(action: { sendAnalyticEvent("'Click Me' clicked") }) {
                    Text("Click Me")
                        .frame(maxWidth: .infinity)
                }
                Button(action: { sendAnalyticEvent("'Click Me Hard' clicked") }) {
                    Text("Click Me Hard")
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 200)
            Divider()
            VStack {
                Text("Logs:")
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                ScrollView {
                    Text(logEvents.joined(separator: "\n\n"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 600, minHeight: 300)
        .padding()
    }
    
    private func handleNotification(_ notification: RemoteNotification) {
        switch notification {
        case .notify(let text):
            logEvents.append("[Notifcation] \(text)")
        case .askApproval(let message):
            let approved = Bool.random()
            logEvents.append("[Approval] \(message.request), approved: \(approved)")
            
            // XPCTransportMessage reply should be called
            message.reply(.success(approved))
        }
    }
    
    private func sendAnalyticEvent(_ reason: String) {
        do {
            try connection.send(AnalyticEvent(reason: reason, date: Date()))
        } catch {
            logEvents.append("Failed to send analytic event")
            print("Failed to send analytic event. Error: \(error)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
