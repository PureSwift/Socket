
// POSIX Socket Option Level
@frozen
public struct SocketOptionLevel: RawRepresentable, Hashable, Codable, Sendable {
    
  /// The raw socket address family identifier.
  @_alwaysEmitIntoClient
  public let rawValue: CInt

  /// Creates a strongly-typed socket address family from a raw address family identifier.
  @_alwaysEmitIntoClient
  public init(rawValue: CInt) { self.rawValue = rawValue }
  
  @_alwaysEmitIntoClient
  private init(_ raw: CInt) { self.init(rawValue: raw) }
}

public extension SocketOptionLevel {
    
    @_alwaysEmitIntoClient
    static var `default`: SocketOptionLevel { SocketOptionLevel(_SOL_SOCKET) }
}

#if os(Linux)
public extension SocketOptionLevel {
    
    @_alwaysEmitIntoClient
    static var netlink: SocketOptionLevel { SocketOptionLevel(_SOL_NETLINK) }
    
    @_alwaysEmitIntoClient
    static var bluetooth: SocketOptionLevel { SocketOptionLevel(_SOL_BLUETOOTH) }
    
    @_alwaysEmitIntoClient
    static var crypto: SocketOptionLevel { SocketOptionLevel(_SOL_ALG) }
}
#endif
