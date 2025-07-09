#if os(Linux) || os(Android)
import CSocket

public extension SocketDescriptor {
    
    /// File descriptor for event notification
    ///
    /// An "eventfd object" can be used as an event wait/notify mechanism by user-space applications, and by the kernel to notify user-space applications of events.
    /// The object contains an unsigned 64-bit integer counter that is maintained by the kernel.
    struct Event: RawRepresentable, Equatable, Hashable, Sendable {
        
        public typealias RawValue = FileDescriptor.RawValue
        
        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }
        
        public let rawValue: RawValue
    }
}

// MARK: - Supporting Types

public extension SocketDescriptor.Event {
    
    /// Flags when opening sockets.
    @frozen
    struct Flags: OptionSet, Hashable, Codable, Sendable {
        
        /// The raw C file events.
        @_alwaysEmitIntoClient
        public let rawValue: CInt

        /// Create a strongly-typed file events from a raw C value.
        @_alwaysEmitIntoClient
        public init(rawValue: CInt) { self.rawValue = rawValue }

        @_alwaysEmitIntoClient
        private init(_ raw: CInt) {
            self.init(rawValue: raw)
        }
    }
}

public extension SocketDescriptor.Event.Flags {
    
    /// Set the close-on-exec (`FD_CLOEXEC`) flag on the new file descriptor.
    ///
    /// See the description of the `O_CLOEXEC` flag in `open(2)` for reasons why this may be useful.
    @_alwaysEmitIntoClient
    static var nonBlocking: SocketDescriptor.Event.Flags { SocketDescriptor.Event.Flags(_EFD_CLOEXEC) }
    
    /// Set the `O_NONBLOCK` file status flag on the new open file description.
    ///
    /// Using this flag saves extra calls to `fcntl(2)` to achieve the same result.
    @_alwaysEmitIntoClient
    static var closeOnExec: SocketDescriptor.Event.Flags { SocketDescriptor.Event.Flags(_EFD_NONBLOCK) }
    
    /// Provide semaphore-like semantics for reads from the new file descriptor.
    @_alwaysEmitIntoClient
    static var semaphore: SocketDescriptor.Event.Flags { SocketDescriptor.Event.Flags(_EFD_SEMAPHORE) }
}

// @available(macOS 10.16, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension SocketDescriptor.Event.Flags: CustomStringConvertible, CustomDebugStringConvertible
{
    /// A textual representation of the open options.
    @inline(never)
    public var description: String {
        let descriptions: [(Element, StaticString)] = [
            (.nonBlocking, ".nonBlocking"),
            (.closeOnExec, ".closeOnExec"),
            (.semaphore, ".semaphore"),
        ]
        return _buildDescription(descriptions)
    }
    
    /// A textual representation of the open options, suitable for debugging.
    public var debugDescription: String { self.description }
}

public extension SocketDescriptor.Event {
    
    @frozen
    struct Counter: RawRepresentable, Equatable, Hashable, Sendable {
        
        public typealias RawValue = UInt64
        
        @_alwaysEmitIntoClient
        public var rawValue: RawValue
        
        @_alwaysEmitIntoClient
        public init(rawValue: RawValue = 0) {
            self.rawValue = rawValue
        }
    }
}

extension SocketDescriptor.Event.Counter: ExpressibleByIntegerLiteral {
    
    public init(integerLiteral value: RawValue) {
        self.init(rawValue: value)
    }
}

extension SocketDescriptor.Event.Counter: CustomStringConvertible, CustomDebugStringConvertible {
    
    public var description: String { rawValue.description }
    
    public var debugDescription: String { description }
}

// MARK: - Operations

extension SocketDescriptor.Event {
    
    internal var fileDescriptor: SocketDescriptor { .init(rawValue: rawValue) }
    
    /**
     `eventfd()` creates an "eventfd object" that can be used as an event wait/notify mechanism by user-space applications, and by the kernel to notify user-space applications of events.
     The object contains an unsigned 64-bit integer (uint64_t) counter that is maintained by the kernel.
     This counter is initialized with the value specified in the argument initval.
     */
    @usableFromInline
    internal static func _events(
        _ counter: CUnsignedInt,
        flags: SocketDescriptor.Event.Flags,
        retryOnInterrupt: Bool
    ) -> Result<SocketDescriptor.Event, Errno> {
        valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
            system_eventfd(counter, flags.rawValue)
        }.map({ SocketDescriptor.Event(rawValue: $0) })
    }
    
    @_alwaysEmitIntoClient
    public init(
        _ counter: CUnsignedInt = 0,
        flags: SocketDescriptor.Event.Flags = [],
        retryOnInterrupt: Bool = true
    ) throws(Errno) {
        self = try Self._events(counter, flags: flags, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    /// Deletes a file descriptor.
    ///
    /// Deletes the file descriptor from the per-process object reference table.
    /// If this is the last reference to the underlying object,
    /// the object will be deactivated.
    ///
    /// The corresponding C function is `close`.
    @_alwaysEmitIntoClient
    public func close() throws(Errno) { try _close().get() }

    @usableFromInline
    internal func _close() -> Result<(), Errno> {
        fileDescriptor._close()
    }

    @usableFromInline
    internal func _read(
      retryOnInterrupt: Bool
    ) -> Result<Counter, Errno> {
        var counter = Counter()
        return withUnsafeMutableBytes(of: &counter.rawValue) {
            fileDescriptor._read(into: $0, retryOnInterrupt: retryOnInterrupt)
        }.map { assert($0 == 8) }.map { _ in counter }
    }
    
    /**
     Each successful `read(2)` returns an 8-byte integer. A read(2) will fail with the error EINVAL if the size of the supplied buffer is less than 8 bytes.
     The value returned by read(2) is in host byte order, i.e., the native byte order for integers on the host machine.
     The semantics of read(2) depend on whether the eventfd counter currently has a nonzero value and whether the EFD_SEMAPHORE flag was specified when creating the eventfd file descriptor:

     - If EFD_SEMAPHORE was not specified and the eventfd counter has a nonzero value, then a read(2) returns 8 bytes containing that value, and the counter's value is reset to zero.
     - If EFD_SEMAPHORE was specified and the eventfd counter has a nonzero value, then a read(2) returns 8 bytes containing the value 1, and the counter's value is decremented by 1.

     If the eventfd counter is zero at the time of the call to read(2), then the call either blocks until the counter becomes nonzero (at which time, the read(2) proceeds as described above) or fails with the error EAGAIN if the file descriptor has been made nonblocking.
     */
    @_alwaysEmitIntoClient
    public func read(
      retryOnInterrupt: Bool = true
    ) throws(Errno) -> Counter {
      try _read(retryOnInterrupt: retryOnInterrupt).get()
    }
    
    /**
     A write(2) call adds the 8-byte integer value supplied in
         its buffer to the counter.  The maximum value that may be
         stored in the counter is the largest unsigned 64-bit value
         minus 1 (i.e., 0xfffffffffffffffe).  If the addition would
         cause the counter's value to exceed the maximum, then the
         write(2) either blocks until a read(2) is performed on the
         file descriptor, or fails with the error EAGAIN if the file
         descriptor has been made nonblocking.

         A write(2) fails with the error EINVAL if the size of the
         supplied buffer is less than 8 bytes, or if an attempt is
         made to write the value 0xffffffffffffffff.
     */
    @_alwaysEmitIntoClient
    public func write(
      _ counter: Counter,
      retryOnInterrupt: Bool = true
    ) throws(Errno) {
      try _write(counter, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    @usableFromInline
    internal func _write(
      _ counter: Counter,
      retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        return withUnsafeBytes(of: counter.rawValue) {
            fileDescriptor._write($0, retryOnInterrupt: retryOnInterrupt)
        }.map { assert($0 == 8) }
    }
}
#endif
