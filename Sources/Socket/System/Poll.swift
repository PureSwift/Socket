import SystemPackage

public extension SocketDescriptor {
    
    /// Poll File Descriptor
    struct Poll: Sendable {
        
        internal fileprivate(set) var bytes: CInterop.PollFileDescriptor
        
        internal init(_ bytes: CInterop.PollFileDescriptor) {
            self.bytes = bytes
        }
        
        // Initialize an events request.
        public init(socket: SocketDescriptor, events: FileEvents) {
            self.init(CInterop.PollFileDescriptor(socket: socket, events: events))
        }
        
        public var socket: SocketDescriptor {
            return SocketDescriptor(rawValue: bytes.fd)
        }
        
        public var events: FileEvents {
            return FileEvents(rawValue: bytes.events)
        }
        
        public var returnedEvents: FileEvents {
            return FileEvents(rawValue: bytes.revents)
        }
    }
}

internal extension CInterop.PollFileDescriptor {
    
    init(socket: SocketDescriptor, events: FileEvents) {
        self.init(fd: socket.rawValue, events: events.rawValue, revents: 0)
    }
}

// MARK: - Poll Operations

extension SocketDescriptor {
    
    /// Wait for some event on a file descriptor.
    ///
    /// - Parameters:
    ///   - events: A bit mask specifying the events the application is interested in for the file descriptor.
    ///   - timeout: Specifies the minimum number of milliseconds that this method will block. Specifying a negative value in timeout means an infinite timeout. Specifying a timeout of zero causes this method to return immediately.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: A bitmask filled by the kernel with the events that actually occurred.
    ///
    /// The corresponding C function is `poll`.
    public func poll(
        for events: FileEvents,
        timeout: Int = 0,
        retryOnInterrupt: Bool = true
    ) throws -> FileEvents {
        try _poll(
            events: events,
            timeout: CInt(timeout),
            retryOnInterrupt: retryOnInterrupt
        ).get()
    }
    
    /// `poll()`
    ///
    /// Wait for some event on a file descriptor.
    @usableFromInline
    internal func _poll(
        events: FileEvents,
        timeout: CInt,
        retryOnInterrupt: Bool
    ) -> Result<FileEvents, Errno> {
        var pollFD = CInterop.PollFileDescriptor(
            fd: self.rawValue,
            events: events.rawValue,
            revents: 0
        )
        return nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            system_poll(&pollFD, 1, timeout)
        }.map { FileEvents(rawValue: pollFD.revents) }
    }
}

extension SocketDescriptor {
    
    /// wait for some event on file descriptors
    @usableFromInline
    internal static func _poll(
        _ pollFDs: inout [Poll],
        timeout: CInt,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        assert(pollFDs.isEmpty == false)
        let count = CInterop.FileDescriptorCount(pollFDs.count)
        return pollFDs.withUnsafeMutableBufferPointer { buffer in
            buffer.withMemoryRebound(to: CInterop.PollFileDescriptor.self) { cBuffer in
                nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
                    system_poll(
                        cBuffer.baseAddress!,
                        count,
                        timeout
                    )
                }
            }
        }
    }
}

extension Array where Element == SocketDescriptor.Poll {
    
    /// Wait for some event on a set of file descriptors.
    ///
    /// - Parameters:
    ///   - fileDescriptors: An array of bit mask specifying the events the application is interested in for the file descriptors.
    ///   - timeout: Specifies the minimum number of milliseconds that this method will block. Specifying a negative value in timeout means an infinite timeout. Specifying a timeout of zero causes this method to return immediately.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns:A array of bitmasks filled by the kernel with the events that actually occurred
    ///     for the corresponding file descriptors.
    ///
    /// The corresponding C function is `poll`.
    public mutating func poll(
        timeout: Int = 0,
        retryOnInterrupt: Bool = true
    ) throws {
        guard isEmpty == false else { return }
        try SocketDescriptor._poll(&self, timeout: CInt(timeout), retryOnInterrupt: retryOnInterrupt).get()
    }
    
    public mutating func reset() {
        for index in 0 ..< count {
            self[index].bytes.revents = 0
        }
    }
}

public extension SocketDescriptor {
    
    /// Wait for some event on a file descriptor.
    ///
    /// - Parameters:
    ///   - events: A bit mask specifying the events the application is interested in for the file descriptor.
    ///   - timeout: Specifies the minimum number of milliseconds that this method will wait.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: A bitmask filled by the kernel with the events that actually occurred.
    ///
    /// The corresponding C function is `poll`.
    func poll(
        for events: FileEvents,
        timeout: UInt, // ms / 1sec
        sleep: UInt64 = 1_000_000, // ns / 1ms
        retryOnInterrupt: Bool = true
    ) async throws -> FileEvents {
        assert(events.isEmpty == false, "Must specify a set of events")
        return try await retry(
            sleep: sleep,
            timeout: timeout,
            condition: { $0.isEmpty == false }) {
            _poll(
                events: events,
                timeout: 0,
                retryOnInterrupt: retryOnInterrupt
            )
        }
    }
}

extension Array where Element == SocketDescriptor.Poll {
    
    /// Wait for some event on a set of file descriptors.
    ///
    /// - Parameters:
    ///   - fileDescriptors: An array of bit mask specifying the events the application is interested in for the file descriptors.
    ///   - timeout: Specifies the minimum number of milliseconds that this method will block.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns:A array of bitmasks filled by the kernel with the events that actually occurred
    ///     for the corresponding file descriptors.
    ///
    /// The corresponding C function is `poll`.
    public mutating func poll(
        timeout: UInt, // ms / 1sec
        sleep: UInt64 = 1_000_000, // ns / 1ms
        retryOnInterrupt: Bool = true
    ) async throws {
        guard isEmpty else { return }
        return try await retry(
            sleep: sleep,
            timeout: timeout
        ) {
            SocketDescriptor._poll(
                &self,
                timeout: 0,
                retryOnInterrupt: retryOnInterrupt
            )
        }
    }
}
