//
//  Log.swift
//  
//
//  Created by Alsey Coleman Miller on 4/2/22.
//

import Foundation

// Socket logging
internal func log(_ message: String) {
    if let logger = Socket.configuration.log {
        logger(message)
    } else {
        #if DEBUG
        if debugLogEnabled {
            NSLog("Socket: " + message)
        }
        #endif
    }
}

#if DEBUG
let debugLogEnabled = ProcessInfo.processInfo.environment["SWIFTSOCKETDEBUG"] == "1"
#endif
