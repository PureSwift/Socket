//
//  LinkLayerSocketAddress.swift
//  
//
//  Created by Alsey Coleman Miller on 10/1/22.
//

#if canImport(Darwin) || os(Linux)
import Foundation
import SystemPackage
import CSocket

/// Unix Socket Address
public struct LinkLayerSocketAddress: SocketAddress, Equatable, Hashable {
        
    public typealias ProtocolID = LinkLayerProtocol
    
    #if canImport(Darwin)
    /// Index type
    public typealias Index = UInt16
    #elseif os(Linux)
    /// Index type
    public typealias Index = Int32
    #endif
    
    internal typealias CSocketAddressType = CInterop.LinkLayerAddress
    
    /// Index
    public let index: Index
    
    /// Address
    public let address: String
    
    internal init(_ cValue: CSocketAddressType) {
        #if canImport(Darwin)
        let index = cValue.sdl_index
        let address = Swift.withUnsafePointer(to: cValue) {
            String(cString: system_link_ntoa($0))
        }
        #elseif os(Linux)
        let index = cValue.sll_ifindex
        let addressLength = Int(cValue.sll_halen)
        let address = Swift.withUnsafePointer(to: cValue.sll_addr) {
            $0.withMemoryRebound(to: CChar.self, capacity: addressLength) { pointer in
                (0 ..< addressLength).reduce("", { $0 + ($0.isEmpty ? "" : ":") + String(format: "%02hhX", pointer[$1]) })
            }
        }
        #endif
        self.index = index
        self.address = address
    }
    
    public func withUnsafePointer<Result>(
        _ body: (UnsafePointer<CInterop.SocketAddress>, UInt32
        ) throws -> Result) rethrows -> Result {
        
        var socketAddress = CSocketAddressType()
        #if canImport(Darwin)
        socketAddress.sdl_index = index
        self.address.withCString {
            system_link_addr($0, &socketAddress)
        }
        #elseif os(Linux)
        socketAddress.sll_ifindex = index
        assertionFailure("Need to implement")
        #endif
        return try socketAddress.withUnsafePointer(body)
    }
        
    public static func withUnsafePointer(
        _ pointer: UnsafeMutablePointer<CInterop.SocketAddress>
    ) -> Self {
        return pointer.withMemoryRebound(to: CSocketAddressType.self, capacity: 1) { pointer in
            Self.init(pointer.pointee)
        }
    }
    
    public static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, UInt32) throws -> ()
    ) rethrows -> Self {
        var socketAddress = CSocketAddressType()
        try socketAddress.withUnsafeMutablePointer(body)
        return Self.init(socketAddress)
    }
}

extension CInterop.LinkLayerAddress: CSocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily { LinkLayerProtocol.family }
}
#endif
