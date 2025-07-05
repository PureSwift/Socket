//
//  NetworkInterface.swift
//  
//
//  Created by Alsey Coleman Miller on 6/8/22.
//

import SystemPackage
import CSocket

/// UNIX Network Interface
public struct NetworkInterface <Address: SocketAddress>: Identifiable, Sendable {
    
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

extension NetworkInterface: Equatable where Address: Equatable { }

extension NetworkInterface: Hashable where Address: Hashable { }

public extension NetworkInterface {
    
    static var interfaces: [Self] {
        get throws(Errno) {
            let interfaceIDs = try NetworkInterfaceID.interfaces
            var linkedList: UnsafeMutablePointer<CInterop.InterfaceLinkedList>? = nil
            guard system_getifaddrs(&linkedList) == 0 else {
                throw Errno.current
            }
            defer { system_freeifaddrs(linkedList) }
            var values = [Self]()
            var linkedListItem = linkedList
            while let value = linkedListItem?.pointee {
                // next item in linked list
                defer { linkedListItem = linkedListItem?.pointee.ifa_next }
                let interfaceName = String(cString: unsafeBitCast(value.ifa_name, to: UnsafePointer<Int8>.self))
                guard let id = interfaceIDs.first(where: { $0.name == interfaceName }) else {
                    assertionFailure("Unknown interface \(interfaceName)")
                    continue
                }
                #if os(Android)
                guard let sa_family = value.ifa_addr?.pointee.sa_family else {
                    continue
                }
                #else
                let sa_family = value.ifa_addr.pointee.sa_family
                #endif
                guard Address.family.rawValue == sa_family else {
                    continue // incompatible address type
                }
                let address = value.ifa_addr.flatMap { Address.withUnsafePointer($0) }
                let netmask = value.ifa_netmask.flatMap { Address.withUnsafePointer($0) }
                guard let address, let netmask else {
                    continue
                }
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

public struct NetworkInterfaceID: Equatable, Hashable, Sendable {
    
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
        let if_name: UnsafeMutablePointer<CChar>? = cValue.if_name
        self.name = if_name.flatMap({ String(cString: $0) }) ?? ""
    }
}
