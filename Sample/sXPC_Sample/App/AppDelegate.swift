//
//  AppDelegate.swift
//  App
//
//  Created by testm1 on 02.04.2021.
//

import Cocoa
import Shared


@main
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let connection = SampleXPCConnection(conneciton: NSXPCConnection(serviceName: "com.alkenso.XPCService"))
        connection.resume()

        let proxy = connection.remoteObjectProxy { error in
            print(error)
        }

        let request = Request(processUID: getuid(), processPID: getpid(), processPath: Bundle.main.executableURL!)
        proxy.perform(request) { response in
            print(response)
        }
    }
}

