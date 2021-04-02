//
//  main.swift
//  XPCService
//
//  Created by testm1 on 02.04.2021.
//

import Foundation
import Shared


struct DummyService: Service {
    func perform(_ request: Request, reply: @escaping (Response) -> Void) {
        reply(.init(allow: true, cache: false))
    }
}


let listener = CreateServiceXPCListener(listener: NSXPCListener.service())
listener.newConnectionHandler = {
    $0.exportedObject = DummyService()
    $0.resume()
    return true
}
listener.resume()

RunLoop.main.run()
