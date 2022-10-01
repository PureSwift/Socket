//
//  IPv4SocketAddress.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

import SystemPackage

/// IPv4 Socket Address
public struct IPv4SocketAddress: SocketAddress, Equatable, Hashable {
    
    public typealias ProtocolID = IPv4Protocol
    
    public var address: IPv4Address
    
    public var port: UInt16
    
    @_alwaysEmitIntoClient
    public init(address: IPv4Address,
                port: UInt16) {
        
        self.address = address
        self.port = port
    }
    
    internal init(_ cValue: CInterop.IPv4SocketAddress) {
        self.init(
            address: IPv4Address(cValue.sin_addr),
            port: cValue.sin_port.networkOrder
        )
    }
    
    public func withUnsafePointer<Result>(
      _ body: (UnsafePointer<CInterop.SocketAddress>, UInt32) throws -> Result
    ) rethrows -> Result {
        
        var socketAddress = CInterop.IPv4SocketAddress()
        socketAddress.sin_family = numericCast(Self.family.rawValue)
        socketAddress.sin_port = port.networkOrder
        socketAddress.sin_addr = address.bytes
        return try socketAddress.withUnsafePointer(body)
    }
    
    public static func withUnsafePointer(
        _ pointer: UnsafeMutablePointer<CInterop.SocketAddress>
    ) -> Self {
        return pointer.withMemoryRebound(to: CInterop.IPv4SocketAddress.self, capacity: 1) { pointer in
            return Self.init(pointer.pointee)
        }
    }
    
    public static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, UInt32) throws -> ()
    ) rethrows -> Self {
        var socketAddress = CInterop.IPv4SocketAddress()
        try socketAddress.withUnsafeMutablePointer(body)
        return Self.init(socketAddress)
    }
}

extension CInterop.IPv4SocketAddress: CSocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily { .ipv4 }
}
