import SystemPackage
@_implementationOnly import CSocket

/// POSIX Socket Type
@frozen
public struct SocketType: RawRepresentable, Hashable, Codable {
    
  /// The raw socket type identifier.
  @_alwaysEmitIntoClient
  public let rawValue: CInt

  /// Creates a strongly-typed socket type from a raw socket type identifier.
  @_alwaysEmitIntoClient
  public init(rawValue: CInt) { self.rawValue = rawValue }
    
  private init(_ cValue: CInterop.SocketType) {
      #if os(Linux)
      self.init(rawValue: numericCast(cValue.rawValue))
      #else
      self.init(rawValue: cValue)
      #endif
  }
}

public extension SocketType {
    
    /// Stream socket
    ///
    /// Provides sequenced, reliable, two-way, connection-based byte streams.
    /// An out-of-band data transmission mechanism may be supported.
    static var stream: SocketType { SocketType(SOCK_STREAM) }
    
    /// Supports datagrams (connectionless, unreliable messages of a fixed maximum length).
    static var datagram: SocketType { SocketType(SOCK_DGRAM) }
    
    /// Provides raw network protocol access.
    static var raw: SocketType { SocketType(SOCK_RAW) }
    
    /// Provides a reliable datagram layer that does not guarantee ordering.
    static var reliableDatagramMessage: SocketType { SocketType(SOCK_RDM) }
    
    /// Provides a sequenced, reliable, two-way connection-based data transmission
    /// path for datagrams of fixed maximum length; a consumer is required to read
    /// an entire packet with each input system call.
    static var sequencedPacket: SocketType { SocketType(SOCK_SEQPACKET) }
}

#if os(Linux)
public extension SocketType {
    
    /// Datagram Congestion Control Protocol
    ///
    /// Linux specific way of getting packets at the dev level.
    static var datagramCongestionControlProtocol: SocketType { SocketType(SOCK_DCCP) }
}
#endif
