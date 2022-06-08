//
//  NetworkInterface.swift
//  
//
//  Created by Alsey Coleman Miller on 6/8/22.
//

import SystemPackage
@_implementationOnly import CSocket

/// UNIX Network Interface
public struct NetworkInterface: Equatable, Hashable, Identifiable {
    
    /// Interface index.
    public let id: UInt32
    
    /// Interface name.
    public let name: String
}

public extension NetworkInterface {
    
    static var interfaces: [NetworkInterface] {
        get throws {
            // get null terminated list
            guard let pointer = system_if_nameindex() else {
                throw Errno.current
            }
            defer { system_if_freenameindex(pointer) }
            // get count
            var count = 0
            while pointer[count].if_name != nil && pointer[count].if_index != 0 {
                count += 1
            }
            // get interfaces
            return (0 ..< count).map { NetworkInterface(pointer[$0]) }
        }
    }
}

internal extension NetworkInterface {
    
    init(_ cValue: CInterop.InterfaceNameIndex) {
        self.id = cValue.if_index
        self.name = String(cString: cValue.if_name)
    }
}
