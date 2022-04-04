//
//  FileEvent.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage

internal extension FileEvents {
    
    static var socket: FileEvents {
        [
            .read,
            .write,
            .error,
            .hangup,
            .invalidRequest
        ]
    }
}
