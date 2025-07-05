//
//  UnixSocketAddress.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

#if !os(Android)
import SystemPackage

/// Unix Socket Address
public struct UnixSocketAddress: SocketAddress, Equatable, Hashable {
    
    public typealias ProtocolID = UnixProtocol
    
    public var path: FilePath
    
    public init(path: FilePath) {
        assert(path.length < 108)
        self.path = path
    }
    
    internal init(_ cValue: CInterop.UnixSocketAddress) {
        self = withUnsafeBytes(of: cValue.sun_path) { pathPointer in
            Self.init(path: FilePath(platformString: pathPointer.baseAddress!.assumingMemoryBound(to: CInterop.PlatformChar.self)))
        }
    }
    
    public func withUnsafePointer<Result, Error>(
      _ body: (UnsafePointer<CInterop.SocketAddress>, UInt32) throws(Error) -> Result
    ) rethrows -> Result where Error: Swift.Error {
        return try path.withPlatformString { platformString in
            var socketAddress = CInterop.UnixSocketAddress()
            socketAddress.sun_family = numericCast(Self.family.rawValue)
            withUnsafeMutableBytes(of: &socketAddress.sun_path) { pathBytes in
                pathBytes
                    .bindMemory(to: CInterop.PlatformChar.self)
                    .baseAddress!
                    .update(from: platformString, count: path.length + 1)
            }
            return try socketAddress.withUnsafePointer(body)
        }
    }
    
    public static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, UInt32) throws -> ()
    ) rethrows -> Self {
        var socketAddress = CInterop.UnixSocketAddress()
        try socketAddress.withUnsafeMutablePointer(body)
        return self.init(socketAddress)
    }
    
    public static func withUnsafePointer(
        _ pointer: UnsafeMutablePointer<CInterop.SocketAddress>
    ) -> Self {
        pointer.withMemoryRebound(to: CInterop.UnixSocketAddress.self, capacity: 1) { pointer in
            Self.init(pointer.pointee)
        }
    }
}

extension CInterop.UnixSocketAddress: CSocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily { .unix }
}
#endif