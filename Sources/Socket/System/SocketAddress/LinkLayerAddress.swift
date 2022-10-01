//
//  LinkLayerAddress.swift
//  
//
//  Created by Alsey Coleman Miller on 10/1/22.
//

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(Linux)
import SystemPackage

/// Unix Socket Address
public struct LinkLayerAddress: SocketAddress, Equatable, Hashable {
        
    public typealias ProtocolID = LinkLayerProtocol
    
    #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    public typealias Index = UInt16
    #elseif os(Linux)
    public typealias Index = UInt32
    #endif
    
    /// Index
    public var index: Index
    
    /// Address
    public var address: String
    
    public func withUnsafePointer<Result>(
        _ body: (UnsafePointer<SystemPackage.CInterop.SocketAddress>, UInt32
        ) throws -> Result) rethrows -> Result {
        
        var socketAddress = CInterop.LinkLayerAddress()
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        socketAddress.sdl_index = index
        self.address.withCString {
            system_link_addr($0, &socketAddress)
        }
        #elseif os(Linux)
        socketAddress.sll_ifindex = index
        //assertionFailure()
        #endif
        return try socketAddress.withUnsafePointer(body)
    }
    
    public static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<SystemPackage.CInterop.SocketAddress>, UInt32) throws -> ()
    ) rethrows -> LinkLayerAddress {
        
        var socketAddress = CInterop.LinkLayerAddress()
        try socketAddress.withUnsafeMutablePointer(body)
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let index = socketAddress.sdl_index
        let cString = system_link_ntoa(&socketAddress)
        let address = String(cString: cString)
        #elseif os(Linux)
        let index = socketAddress.sll_ifindex
        let address = "" // FIXME:
        //assertionFailure()
        #endif
        return self.init(
            index: index,
            address: address
        )
    }
}

extension CInterop.LinkLayerAddress: CSocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily { LinkLayerProtocol.family }
}
#endif
