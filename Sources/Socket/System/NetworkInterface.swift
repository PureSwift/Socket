//
//  NetworkInterface.swift
//  
//
//  Created by Alsey Coleman Miller on 6/8/22.
//

import SystemPackage
import CSocket

/// UNIX Network Interface
public struct NetworkInterface <Address: SocketAddress>: Identifiable {
    
    public typealias ID = NetworkInterfaceID
    
    /// Interface index.
    public let id: ID
    
    /// Flags from SIOCGIFFLAGS
    public let flags: UInt32
    
    /// Address of interface
    public let address: Address
    
    /// Netmask of interface
    public let netmask: Address?
}

public extension NetworkInterface {
    
    static var interfaces: [Self] {
        get throws {
            let interfaceIDs = try NetworkInterfaceID.interfaces
            var linkedList: UnsafeMutablePointer<CInterop.InterfaceLinkedList>? = nil
            guard system_getifaddrs(&linkedList) == 0 else {
                return []
            }
            defer { system_freeifaddrs(linkedList) }
            var values = [Self]()
            var linkedListItem = linkedList
            while let value = linkedListItem?.pointee {
                // next item in linked list
                defer { linkedListItem = linkedListItem?.pointee.ifa_next }
                let interfaceName = String(cString: .init(value.ifa_name))
                guard let id = interfaceIDs.first(where: { $0.name == interfaceName }) else {
                    assertionFailure("Unknown interface \(interfaceName)")
                    continue
                }
                guard Address.family.rawValue == value.ifa_addr.pointee.sa_family else {
                    continue // incompatible address type
                }
                let address = Address.withUnsafePointer(value.ifa_addr)
                let netmask = value.ifa_netmask == nil ? nil : Address.withUnsafePointer(value.ifa_netmask)
                let interface = Self.init(
                    id: id,
                    flags: value.ifa_flags,
                    address: address,
                    netmask: netmask
                )
                values.append(interface)
            }
            return values
        }
    }
}

// MARK: - Supporting Types

public struct NetworkInterfaceID: Equatable, Hashable {
    
    /// Interface index.
    public let index: UInt32
    
    /// Interface name.
    public let name: String
}

public extension NetworkInterfaceID {
    
    static var interfaces: [NetworkInterfaceID] {
        get throws(Errno) {
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
            return (0 ..< count).map { NetworkInterfaceID(pointer[$0]) }
        }
    }
}

internal extension NetworkInterfaceID {
    
    init(_ cValue: CInterop.InterfaceNameIndex) {
        self.index = cValue.if_index
        self.name = String(cString: cValue.if_name)
    }
}
