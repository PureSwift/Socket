//
//  EpollEventQueue.swift
//  Socket
//

#if os(Linux) || os(Android)
import CSocket
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif
import SystemPackage

/// Event queue backed by `epoll(7)`.
///
/// Registrations are level-triggered to match `poll(2)` semantics.
internal struct EpollEventQueue: EventQueue, @unchecked Sendable {

    static var isStateful: Bool { true }

    private let queueFileDescriptor: CInt

    private let wakeEvent: SocketDescriptor.Event

    private var eventBuffer: [CInterop.EPollEvent]

    private var readiness: [SocketReadiness]

    init(maxEvents: Int) throws(Errno) {
        let queueFileDescriptor = system_epoll_create1(_EPOLL_CLOEXEC)
        guard queueFileDescriptor != -1 else {
            throw Errno(rawValue: system_errno)
        }
        self.queueFileDescriptor = queueFileDescriptor
        do {
            self.wakeEvent = try SocketDescriptor.Event(flags: [.nonBlocking, .closeOnExec])
        } catch {
            _ = system_close(queueFileDescriptor)
            throw error
        }
        self.eventBuffer = .init(repeating: .init(), count: max(1, maxEvents))
        self.readiness = []
        self.readiness.reserveCapacity(maxEvents)
        // register event descriptor to interrupt a blocking wait
        do {
            try control(_EPOLL_CTL_ADD, wakeEvent.rawValue, mask: _EPOLLIN)
        } catch {
            _ = system_close(queueFileDescriptor)
            try? wakeEvent.close()
            throw error
        }
    }

    mutating func close() {
        try? wakeEvent.close()
        _ = system_close(queueFileDescriptor)
        eventBuffer.removeAll()
        readiness.removeAll()
    }

    mutating func add(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno) {
        try control(_EPOLL_CTL_ADD, fileDescriptor.rawValue, mask: Self.mask(for: events))
    }

    mutating func update(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno) {
        try control(_EPOLL_CTL_MOD, fileDescriptor.rawValue, mask: Self.mask(for: events))
    }

    mutating func remove(_ fileDescriptor: SocketDescriptor) throws(Errno) {
        do {
            try control(_EPOLL_CTL_DEL, fileDescriptor.rawValue, mask: nil)
        } catch {
            // tolerate removing descriptors that are missing or already closed
            guard error == .noSuchFileOrDirectory || error == .badFileDescriptor else {
                throw error
            }
        }
    }

    mutating func wait<T>(
        timeout: Int?,
        _ body: (UnsafeBufferPointer<SocketReadiness>) throws -> T
    ) throws -> T {
        var eventCount: CInt
        repeat {
            eventCount = eventBuffer.withUnsafeMutableBufferPointer { buffer in
                system_epoll_wait(
                    queueFileDescriptor,
                    buffer.baseAddress!,
                    CInt(buffer.count),
                    CInt(timeout ?? -1)
                )
            }
            if eventCount == -1 {
                let error = Errno(rawValue: system_errno)
                guard error == .interrupted else { throw error }
            }
        } while eventCount == -1
        readiness.removeAll(keepingCapacity: true)
        for index in 0 ..< Int(eventCount) {
            let event = eventBuffer[index]
            let fileDescriptor = event.data.fd
            guard fileDescriptor != wakeEvent.rawValue else {
                _ = try? wakeEvent.read() // drain wake counter
                continue
            }
            var events = FileEvents()
            if event.events & _EPOLLIN != 0 { events.insert(.read) }
            if event.events & _EPOLLPRI != 0 { events.insert(.readUrgent) }
            if event.events & _EPOLLOUT != 0 { events.insert(.write) }
            if event.events & _EPOLLERR != 0 { events.insert(.error) }
            if event.events & _EPOLLHUP != 0 { events.insert(.hangup) }
            readiness.append(
                .init(
                    fileDescriptor: SocketDescriptor(rawValue: fileDescriptor),
                    events: events
                )
            )
        }
        return try readiness.withUnsafeBufferPointer(body)
    }

    func wake() throws(Errno) {
        try wakeEvent.write(1)
    }

    private func control(_ operation: CInt, _ fileDescriptor: CInt, mask: UInt32?) throws(Errno) {
        var event = CInterop.EPollEvent()
        if let mask {
            event.events = mask
            event.data.fd = fileDescriptor
        }
        guard system_epoll_ctl(queueFileDescriptor, operation, fileDescriptor, &event) != -1 else {
            throw Errno(rawValue: system_errno)
        }
    }

    private static func mask(for events: FileEvents) -> UInt32 {
        var mask: UInt32 = 0
        if events.contains(.read) { mask |= _EPOLLIN }
        if events.contains(.readUrgent) { mask |= _EPOLLPRI }
        if events.contains(.write) { mask |= _EPOLLOUT }
        return mask
    }
}
#endif
