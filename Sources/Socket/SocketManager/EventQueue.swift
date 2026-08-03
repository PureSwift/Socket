//
//  EventQueue.swift
//  Socket
//

import SystemPackage

/// A kernel-side registration of file descriptors and interest masks.
internal protocol EventQueue: Sendable {

    /// Whether this queue holds registration state across waits.
    static var isStateful: Bool { get }

    /// Creates the underlying kernel queue.
    init(maxEvents: Int) throws(Errno)

    /// Closes the underlying kernel queue.
    mutating func close()

    /// Registers a file descriptor with the specified interest mask.
    mutating func add(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno)

    /// Updates the interest mask of a registered file descriptor.
    mutating func update(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno)

    /// Deregisters a file descriptor.
    mutating func remove(_ fileDescriptor: SocketDescriptor) throws(Errno)

    /// Waits up to `timeout` milliseconds for events.
    ///
    /// A timeout of `0` polls and returns immediately, `nil` blocks indefinitely.
    /// The buffer of ready descriptors is only valid for the duration of `body`.
    mutating func wait<T>(
        timeout: Int?,
        _ body: (UnsafeBufferPointer<SocketReadiness>) throws -> T
    ) throws -> T

    /// Interrupts an in-flight blocking ``wait(timeout:_:)``.
    func wake() throws(Errno)
}

/// Events reported by an ``EventQueue`` for a single file descriptor.
internal struct SocketReadiness: Equatable, Hashable, Sendable {

    let fileDescriptor: SocketDescriptor

    let events: FileEvents
}
