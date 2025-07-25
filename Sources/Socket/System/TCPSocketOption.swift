/// TCP Socket Option ID
@frozen
public struct TCPSocketOption: RawRepresentable, Equatable, Hashable, SocketOptionID, Sendable {
    
    @_alwaysEmitIntoClient
    public static var optionLevel: SocketOptionLevel { .tcp }
    
    /// The raw socket option identifier.
    @_alwaysEmitIntoClient
    public let rawValue: CInt

    /// Creates a TCP socket option from a raw option identifier.
    @_alwaysEmitIntoClient
    public init(rawValue: CInt) { self.rawValue = rawValue }
    
    @_alwaysEmitIntoClient
    private init(_ raw: CInt) { self.init(rawValue: raw) }
}

public extension TCPSocketOption {
    
    /// TCP_NODELAY - Disable Nagle's algorithm.
    ///
    /// When enabled, this option disables the Nagle algorithm which delays
    /// transmission of data to coalesce small packets. This can improve
    /// latency for interactive applications.
    @_alwaysEmitIntoClient
    static var noDelay: TCPSocketOption { TCPSocketOption(_TCP_NODELAY) }
}

/// TCP Socket Options
public extension TCPSocketOption {
    
    /// Disable Nagle's algorithm (TCP_NODELAY).
    ///
    /// When enabled, this option disables the Nagle algorithm which delays
    /// transmission of data to coalesce small packets. This can improve
    /// latency for interactive applications at the cost of potentially
    /// increased network traffic.
    @frozen
    struct NoDelay: BooleanSocketOption, Equatable, Hashable, ExpressibleByBooleanLiteral, Sendable {
        
        @_alwaysEmitIntoClient
        public static var id: TCPSocketOption { .noDelay }
        
        public var boolValue: Bool
        
        @_alwaysEmitIntoClient
        public init(_ boolValue: Bool) {
            self.boolValue = boolValue
        }
    }
}