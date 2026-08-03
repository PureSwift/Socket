//
//  PollEventQueue.swift
//  Socket
//

import SystemPackage

/// Event queue backed by `poll(2)`.
///
/// The kernel holds no state between waits, so the descriptor set
/// is submitted on every call to ``wait(timeout:_:)``.
internal struct PollEventQueue: EventQueue, Sendable {

    static var isStateful: Bool { false }

    private var descriptors: [SocketDescriptor.Poll]

    private var readiness: [SocketReadiness]

    init(maxEvents: Int) throws(Errno) {
        self.descriptors = []
        self.readiness = []
        self.descriptors.reserveCapacity(maxEvents)
        self.readiness.reserveCapacity(maxEvents)
    }

    mutating func close() {
        descriptors.removeAll()
        readiness.removeAll()
    }

    mutating func add(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno) {
        guard index(of: fileDescriptor) == nil else {
            throw Errno.fileExists
        }
        descriptors.append(.init(socket: fileDescriptor, events: events))
    }

    mutating func update(_ fileDescriptor: SocketDescriptor, events: FileEvents) throws(Errno) {
        guard let index = index(of: fileDescriptor) else {
            throw Errno.noSuchFileOrDirectory
        }
        descriptors[index] = .init(socket: fileDescriptor, events: events)
    }

    mutating func remove(_ fileDescriptor: SocketDescriptor) throws(Errno) {
        guard let index = index(of: fileDescriptor) else {
            throw Errno.noSuchFileOrDirectory
        }
        descriptors.remove(at: index)
    }

    mutating func wait<T>(
        timeout: Int?,
        _ body: (UnsafeBufferPointer<SocketReadiness>) throws -> T
    ) throws -> T {
        descriptors.reset()
        try descriptors.poll(timeout: timeout ?? -1)
        readiness.removeAll(keepingCapacity: true)
        for descriptor in descriptors where descriptor.returnedEvents.isEmpty == false {
            readiness.append(
                .init(
                    fileDescriptor: descriptor.socket,
                    events: descriptor.returnedEvents
                )
            )
        }
        return try readiness.withUnsafeBufferPointer(body)
    }

    func wake() throws(Errno) {
        // a zero-timeout wait never blocks, nothing to interrupt
    }

    private func index(of fileDescriptor: SocketDescriptor) -> Int? {
        descriptors.firstIndex(where: { $0.socket == fileDescriptor })
    }
}
