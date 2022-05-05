#if os(Linux)
@_implementationOnly import CSocket

/// Flags when opening sockets.
@frozen
public struct SocketFlags: OptionSet, Hashable, Codable {
    
    /// The raw C file events.
    @_alwaysEmitIntoClient
    public let rawValue: CInt

    /// Create a strongly-typed file events from a raw C value.
    @_alwaysEmitIntoClient
    public init(rawValue: CInt) { self.rawValue = rawValue }

    private init(_ cValue: CInterop.SocketType) { 
        self.init(rawValue: numericCast(cValue.rawValue)) 
    }
}

public extension SocketFlags {
    
    /// Set the `O_NONBLOCK` file status flag on the open file description referred to by the new file
    /// descriptor.  Using this flag saves extra calls to `fcntl()` to achieve the same result.
    static var nonBlocking: SocketFlags { SocketFlags(SOCK_NONBLOCK) }
    
    /// Set the close-on-exec (`FD_CLOEXEC`) flag on the new file descriptor.
    static var closeOnExec: SocketFlags { SocketFlags(SOCK_CLOEXEC) }
}

// @available(macOS 10.16, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension SocketFlags: CustomStringConvertible, CustomDebugStringConvertible
{
    /// A textual representation of the open options.
    @inline(never)
    public var description: String {
        let descriptions: [(Element, StaticString)] = [
            (.nonBlocking, ".nonBlocking"),
            (.closeOnExec, ".closeOnExec")
        ]
        return _buildDescription(descriptions)
    }
    
    /// A textual representation of the open options, suitable for debugging.
    public var debugDescription: String { self.description }
}
#endif
