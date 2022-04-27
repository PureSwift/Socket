//
//  IPv6SocketAddress.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

import SystemPackage

/// IPv6 Socket Address
public struct IPv6SocketAddress: SocketAddress, Equatable, Hashable {
    
    public typealias ProtocolID = IPv6Protocol
    
    public var address: IPv6Address
    
    public var port: UInt16
    
    @_alwaysEmitIntoClient
    public init(address: IPv6Address,
                port: UInt16) {
        
        self.address = address
        self.port = port
    }
    
    public func withUnsafePointer<Result>(
      _ body: (UnsafePointer<CInterop.SocketAddress>, UInt32) throws -> Result
    ) rethrows -> Result {
        
        var socketAddress = CInterop.IPv6SocketAddress()
        socketAddress.sin6_family = numericCast(Self.family.rawValue)
        socketAddress.sin6_port = port.networkOrder
        socketAddress.sin6_addr = address.bytes
        return try socketAddress.withUnsafePointer(body)
    }
    
    public static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, UInt32) throws -> ()
    ) rethrows -> Self {
        var socketAddress = CInterop.IPv6SocketAddress()
        try socketAddress.withUnsafeMutablePointer(body)
        return Self.init(
            address: IPv6Address(socketAddress.sin6_addr),
            port: socketAddress.sin6_port.networkOrder
        )
    }
}

extension CInterop.IPv6SocketAddress: CSocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily { .ipv6 }
}
