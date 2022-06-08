
/// POSIX Socket Option ID
public protocol SocketOptionID: RawRepresentable {
        
    static var optionLevel: SocketOptionLevel { get }
    
    init?(rawValue: Int32)
    
    var rawValue: Int32 { get }
}

@frozen
public struct GenericSocketOption: RawRepresentable, Equatable, Hashable, SocketOptionID {
    
    @_alwaysEmitIntoClient
    public static var optionLevel: SocketOptionLevel { .default }
    
    /// The raw socket address family identifier.
    @_alwaysEmitIntoClient
    public let rawValue: CInt

    /// Creates a strongly-typed socket address family from a raw address family identifier.
    @_alwaysEmitIntoClient
    public init(rawValue: CInt) { self.rawValue = rawValue }
    
    @_alwaysEmitIntoClient
    private init(_ raw: CInt) { self.init(rawValue: raw) }
}

public extension GenericSocketOption {
    
    /// Enable socket debugging.
    @_alwaysEmitIntoClient
    static var debug: GenericSocketOption { GenericSocketOption(_SO_DEBUG) }
    
    /// Enable sending of keep-alive messages on connection-oriented sockets.
    ///
    /// Expects an integer boolean flag.
    @_alwaysEmitIntoClient
    static var keepAlive: GenericSocketOption { GenericSocketOption(_SO_KEEPALIVE) }
    
    /**
     Allow reuse of local addresses when binding,
     
     Indicates that the rules used in validating addresses
     supplied in a  ``SocketDescriptor.bind(_:retryOnInterrupt:)`` call should allow reuse of local
     addresses.  For ``IPv4Protocol`` sockets this means that a socket
     may bind, except when there is an active listening socket
     bound to the address.  When the listening socket is bound
     to ``IPv4Address.any`` with a specific port then it is not possible
     to bind to this port for any local address.  Argument is
     an integer boolean flag.
     */
    @_alwaysEmitIntoClient
    static var reuseAddress: GenericSocketOption { GenericSocketOption(_SO_REUSEADDR) }
}
