//
//  KqueueEventQueue.swift
//  Socket
//

#if canImport(Darwin)
import Darwin
import SystemPackage

/// Event queue backed by `kqueue(2)`.
///
/// Registrations are level-triggered to match `poll(2)` semantics.
internal struct KqueueEventQueue: EventQueue, @unchecked Sendable {

    static var isStateful: Bool { true }

    private let queueFileDescriptor: CInt

    private var eventBuffer: [CInterop.KernelEvent]

    private var readiness: [SocketReadiness]

    private var readinessIndices: [SocketDescriptor: Int]

    init(maxEvents: Int) throws(Errno) {
        let queueFileDescriptor = system_kqueue()
        guard queueFileDescriptor != -1 else {
            throw Errno(rawValue: system_errno)
        }
        self.queueFileDescriptor = queueFileDescriptor
        self.eventBuffer = .init(repeating: .init(), count: max(1, maxEvents))
        self.readiness = []
        self.readinessIndices = [:]
        self.readiness.reserveCapacity(maxEvents)
        // register user event to interrupt a blocking wait
        var wakeEvent = CInterop.KernelEvent(
            ident: 0,
            filter: Int16(EVFILT_USER),
            flags: UInt16(EV_ADD | EV_CLEAR),
            fflags: 0,
            data: 0,
            udata: nil
        )
        guard system_kevent(queueFileDescriptor, &wakeEvent, 1, nil, 0, nil) != -1 else {
            let error = Errno(rawValue: system_errno)
            _ = system_close(queueFileDescriptor)
            throw error
        }
    }

    mutating func close() {
        _ = system_close(queueFileDescriptor)
        eventBuffer.removeAll()
        readiness.removeAll()
        readinessIndices.removeAll()
    }

    mutating func add(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno) {
        try apply(fileDescriptor, filter: EVFILT_READ, isDesired: events.contains(.read), isRegistered: false)
        try apply(fileDescriptor, filter: EVFILT_WRITE, isDesired: events.contains(.write), isRegistered: false)
    }

    mutating func update(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno) {
        try apply(fileDescriptor, filter: EVFILT_READ, isDesired: events.contains(.read), isRegistered: true)
        try apply(fileDescriptor, filter: EVFILT_WRITE, isDesired: events.contains(.write), isRegistered: true)
    }

    mutating func remove(_ fileDescriptor: SocketDescriptor) throws(Errno) {
        try apply(fileDescriptor, filter: EVFILT_READ, isDesired: false, isRegistered: true)
        try apply(fileDescriptor, filter: EVFILT_WRITE, isDesired: false, isRegistered: true)
    }

    mutating func wait<T>(
        timeout: Int?,
        _ body: (UnsafeBufferPointer<SocketReadiness>) throws -> T
    ) throws -> T {
        var eventCount: CInt
        repeat {
            eventCount = eventBuffer.withUnsafeMutableBufferPointer { buffer in
                if let timeout {
                    var timeSpec = timespec(
                        tv_sec: timeout / 1000,
                        tv_nsec: (timeout % 1000) * 1_000_000
                    )
                    return system_kevent(queueFileDescriptor, nil, 0, buffer.baseAddress, CInt(buffer.count), &timeSpec)
                } else {
                    return system_kevent(queueFileDescriptor, nil, 0, buffer.baseAddress, CInt(buffer.count), nil)
                }
            }
            if eventCount == -1 {
                let error = Errno(rawValue: system_errno)
                guard error == .interrupted else { throw error }
            }
        } while eventCount == -1
        readiness.removeAll(keepingCapacity: true)
        readinessIndices.removeAll(keepingCapacity: true)
        for index in 0 ..< Int(eventCount) {
            let event = eventBuffer[index]
            guard CInt(event.filter) != EVFILT_USER else {
                continue // wake notification
            }
            let fileDescriptor = SocketDescriptor(rawValue: CInt(event.ident))
            var events = FileEvents()
            switch CInt(event.filter) {
            case EVFILT_READ:
                events.insert(.read)
                // report hangup only once pending data is drained, matching POLLHUP
                if event.flags & UInt16(EV_EOF) != 0, event.data == 0 {
                    events.insert(.hangup)
                }
            case EVFILT_WRITE:
                events.insert(.write)
                if event.flags & UInt16(EV_EOF) != 0 {
                    events.insert(.hangup)
                }
            default:
                break
            }
            if event.flags & UInt16(EV_ERROR) != 0 {
                events.insert(.error)
            }
            // kqueue reports read and write as separate filters, coalesce per descriptor
            if let existingIndex = readinessIndices[fileDescriptor] {
                readiness[existingIndex] = .init(
                    fileDescriptor: fileDescriptor,
                    events: readiness[existingIndex].events.union(events)
                )
            } else {
                readinessIndices[fileDescriptor] = readiness.count
                readiness.append(.init(fileDescriptor: fileDescriptor, events: events))
            }
        }
        return try readiness.withUnsafeBufferPointer(body)
    }

    func wake() throws(Errno) {
        var event = CInterop.KernelEvent(
            ident: 0,
            filter: Int16(EVFILT_USER),
            flags: 0,
            fflags: CUnsignedInt(NOTE_TRIGGER),
            data: 0,
            udata: nil
        )
        guard system_kevent(queueFileDescriptor, &event, 1, nil, 0, nil) != -1 else {
            throw Errno(rawValue: system_errno)
        }
    }

    private func apply(
        _ fileDescriptor: SocketDescriptor,
        filter: CInt,
        isDesired: Bool,
        isRegistered: Bool
    ) throws(Errno) {
        guard isDesired || isRegistered else { return }
        var event = CInterop.KernelEvent(
            ident: UInt(fileDescriptor.rawValue),
            filter: Int16(filter),
            flags: UInt16(isDesired ? EV_ADD : EV_DELETE),
            fflags: 0,
            data: 0,
            udata: nil
        )
        guard system_kevent(queueFileDescriptor, &event, 1, nil, 0, nil) != -1 else {
            let error = Errno(rawValue: system_errno)
            // tolerate removing filters that are missing or already closed
            guard isDesired == false,
                error == .noSuchFileOrDirectory || error == .badFileDescriptor else {
                throw error
            }
            return
        }
    }
}
#endif
