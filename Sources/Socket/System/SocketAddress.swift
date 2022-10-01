import SystemPackage

/// Socket Address
public protocol SocketAddress {
    
    /// Socket Protocol
    associatedtype ProtocolID: SocketProtocol
    
    /// Unsafe pointer closure
    func withUnsafePointer<Result>(
      _ body: (UnsafePointer<CInterop.SocketAddress>, UInt32) throws -> Result
    ) rethrows -> Result
    
    static func withUnsafePointer(
        _ pointer: UnsafeMutablePointer<CInterop.SocketAddress>
    ) -> Self
    
    static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, UInt32) throws -> ()
    ) rethrows -> Self
}

public extension SocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily {
        return ProtocolID.family
    }
}
