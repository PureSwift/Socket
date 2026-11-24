//
//  EventRegistry.swift
//  Socket
//

import Foundation
import SystemPackage

/// The kernel event queue, shared by the manager, each socket and the monitor thread.
///
/// Registrations are made from whichever actor knows what a socket is waiting for, while
/// the monitor thread blocks in ``EventQueue/wait(timeout:_:)``. A stateful queue is a value
/// handle to a kernel object: copies share its registrations but each owns its own event
/// buffers, so the monitor thread waits on a copy of its own (``makeWaiter()``) while
/// registrations go through this one under a lock.
///
/// Each registration records the socket that owns it. A descriptor number is reused as soon
/// as it is closed, so a socket that is no longer the owner, because it was removed and its
/// number given to a new socket, cannot change the new socket's registration.
internal final class EventRegistry: @unchecked Sendable {

    private let lock = NSLock()

    private var queue: PlatformEventQueue

    private var entries = [SocketDescriptor: Entry]()

    init(maxEvents: Int) throws(Errno) {
        self.queue = try PlatformEventQueue(maxEvents: maxEvents)
    }

    /// A copy of the queue for the monitor thread to wait on.
    ///
    /// Only meaningful for a stateful queue, whose copies share their registrations.
    func makeWaiter() -> PlatformEventQueue {
        lock.lock()
        defer { lock.unlock() }
        return queue
    }

    /// Register a descriptor for its owner, replacing any earlier registration of the number.
    func register(
        _ fileDescriptor: SocketDescriptor,
        events: FileEvents,
        owner: AnyObject
    ) throws(Errno) {
        lock.lock()
        defer { lock.unlock() }
        if entries.removeValue(forKey: fileDescriptor)?.events != nil {
            try? queue.remove(fileDescriptor)
        }
        try queue.add(fileDescriptor, events: events)
        entries[fileDescriptor] = Entry(owner: ObjectIdentifier(owner), events: events)
    }

    /// Deregister a descriptor, whoever owns it.
    func deregister(_ fileDescriptor: SocketDescriptor) {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries.removeValue(forKey: fileDescriptor),
            entry.events != nil else {
            return
        }
        try? queue.remove(fileDescriptor)
    }

    /// Change the events a descriptor is registered for.
    ///
    /// `nil` takes the descriptor out of the kernel queue while keeping it owned, for a socket
    /// whose condition the queue reports whatever it is registered for, such as the hangup of
    /// a socket that is not connected yet. Ignored unless `owner` still owns the descriptor.
    func setEvents(
        _ events: FileEvents?,
        for fileDescriptor: SocketDescriptor,
        owner: AnyObject
    ) throws(Errno) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[fileDescriptor],
            entry.owner == ObjectIdentifier(owner),
            entry.events != events else {
            return
        }
        switch (entry.events, events) {
        case (nil, nil):
            break
        case let (nil, events?):
            try queue.add(fileDescriptor, events: events)
        case (_?, nil):
            try queue.remove(fileDescriptor)
        case let (_?, events?):
            try queue.update(fileDescriptor, events: events)
        }
        entry.events = events
        entries[fileDescriptor] = entry
    }

    /// Poll without blocking, for a queue that holds no state between waits.
    func poll() throws -> [SocketReadiness] {
        lock.lock()
        defer { lock.unlock() }
        return try queue.wait(timeout: 0) { Array($0) }
    }
}

private extension EventRegistry {

    struct Entry {

        let owner: ObjectIdentifier

        /// The events registered with the kernel queue, `nil` while taken out of it.
        var events: FileEvents?
    }
}
