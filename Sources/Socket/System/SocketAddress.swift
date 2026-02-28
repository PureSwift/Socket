import SystemPackage

/// Socket Address
public protocol SocketAddress: Sendable {
    
    /// Socket Protocol
    associatedtype ProtocolID: SocketProtocol
    
    /// Unsafe pointer closure
    func withUnsafePointer<Result, Error>(
      _ body: (UnsafePointer<CInterop.SocketAddress>, CInterop.SocketLength) throws(Error) -> Result
    ) rethrows -> Result where Error: Swift.Error
    
    static func withUnsafePointer(
        _ pointer: UnsafeMutablePointer<CInterop.SocketAddress>
    ) -> Self
    
    static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, CInterop.SocketLength) throws -> ()
    ) rethrows -> Self
}

public extension SocketAddress {
    
    @_alwaysEmitIntoClient
    static var family: SocketAddressFamily {
        return ProtocolID.family
    }
}
