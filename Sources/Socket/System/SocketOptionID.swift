
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
    
    @_alwaysEmitIntoClient
    static var debug: GenericSocketOption { GenericSocketOption(_SO_DEBUG) }
    
    @_alwaysEmitIntoClient
    static var keepAlive: GenericSocketOption { GenericSocketOption(_SO_KEEPALIVE) }
}
