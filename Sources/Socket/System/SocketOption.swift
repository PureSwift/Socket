
/// POSIX Socket Option ID
public protocol SocketOption {
    
    associatedtype ID: SocketOptionID
    
    static var id: ID { get }
    
    func withUnsafeBytes<Result>(_ pointer: ((UnsafeRawBufferPointer) throws -> (Result))) rethrows -> Result
    
    static func withUnsafeBytes(
        _ body: (UnsafeMutableRawBufferPointer) throws -> ()
    ) rethrows -> Self
}

public protocol BooleanSocketOption: SocketOption {
    
    init(_ boolValue: Bool)
    
    var boolValue: Bool { get }
}

extension BooleanSocketOption where Self: ExpressibleByBooleanLiteral {
    
    @_alwaysEmitIntoClient
    public init(booleanLiteral boolValue: Bool) {
        self.init(boolValue)
    }
}

public extension BooleanSocketOption {
    
    func withUnsafeBytes<Result>(_ pointer: ((UnsafeRawBufferPointer) throws -> (Result))) rethrows -> Result {
        return try Swift.withUnsafeBytes(of: boolValue.cInt) { bufferPointer in
            try pointer(bufferPointer)
        }
    }
    
    static func withUnsafeBytes(_ body: (UnsafeMutableRawBufferPointer) throws -> ()) rethrows -> Self {
        var value: CInt = 0
        try Swift.withUnsafeMutableBytes(of: &value, body)
        return Self.init(Bool(value))
    }
}

/// Platform Socket Option
public extension GenericSocketOption {
    
    /// Enable socket debugging.
    @frozen
    struct Debug: BooleanSocketOption, Equatable, Hashable, ExpressibleByBooleanLiteral {
        
        @_alwaysEmitIntoClient
        public static var id: GenericSocketOption { .debug }
        
        public var boolValue: Bool
        
        @_alwaysEmitIntoClient
        public init(_ boolValue: Bool) {
            self.boolValue = boolValue
        }
    }
    
    /// Enable sending of keep-alive messages on connection-oriented sockets.
    @frozen
    struct KeepAlive: BooleanSocketOption, Equatable, Hashable, ExpressibleByBooleanLiteral {
        
        @_alwaysEmitIntoClient
        public static var id: GenericSocketOption { .keepAlive }
        
        public var boolValue: Bool
        
        @_alwaysEmitIntoClient
        public init(_ boolValue: Bool) {
            self.boolValue = boolValue
        }
    }
    
    // Allow reuse of local addresses when binding.
    @frozen
    struct ReuseAddress: BooleanSocketOption, Equatable, Hashable, ExpressibleByBooleanLiteral {
        
        @_alwaysEmitIntoClient
        public static var id: GenericSocketOption { .reuseAddress }
        
        public var boolValue: Bool
        
        @_alwaysEmitIntoClient
        public init(_ boolValue: Bool) {
            self.boolValue = boolValue
        }
    }
}
