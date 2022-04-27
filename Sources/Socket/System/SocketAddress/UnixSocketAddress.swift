//
//  UnixSocketAddress.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

import SystemPackage

/// Unix Socket Address
public struct UnixSocketAddress: SocketAddress, Equatable, Hashable {
    
    public typealias ProtocolID = UnixProtocol
    
    public var path: FilePath
    
    @_alwaysEmitIntoClient
    public init(path: FilePath) {
        self.path = path
    }
    
    public func withUnsafePointer<Result>(
      _ body: (UnsafePointer<CInterop.SocketAddress>, UInt32) throws -> Result
    ) rethrows -> Result {
        return try path.withPlatformString { platformString in
            var socketAddress = CInterop.UnixSocketAddress()
            socketAddress.sun_family = numericCast(Self.family.rawValue)
            withUnsafeMutableBytes(of: &socketAddress.sun_path) { pathBytes in
                pathBytes
                    .bindMemory(to: CInterop.PlatformChar.self)
                    .baseAddress!
                    .assign(from: platformString, count: path.length)
            }
            return try socketAddress.withUnsafePointer(body)
        }
    }
    
    public static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, UInt32) throws -> ()
    ) rethrows -> Self {
        var socketAddress = CInterop.UnixSocketAddress()
        try socketAddress.withUnsafeMutablePointer(body)
        return withUnsafeBytes(of: socketAddress.sun_path) { pathPointer in
            Self.init(path: FilePath(platformString: pathPointer.baseAddress!.assumingMemoryBound(to: CInterop.PlatformChar.self)))
        }
    }
}

extension CInterop.UnixSocketAddress: CSocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily { .unix }
}
