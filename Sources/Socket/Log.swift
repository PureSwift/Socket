//
//  Log.swift
//  
//
//  Created by Alsey Coleman Miller on 4/2/22.
//

import Foundation

// Socket logging
internal func log(_ message: String) {
    if ProcessInfo.processInfo.environment["SWIFTSOCKETDEBUG"] == "1" {
        NSLog(message)
    }
}
