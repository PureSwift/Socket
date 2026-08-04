import Foundation
import Testing
import SystemPackage
@testable import Socket

@Suite("EventQueue Tests")
struct EventQueueTests {

    @Test("Poll backend conformance")
    func pollEventQueue() throws {
        try Self.validate(PollEventQueue.self)
    }

    #if canImport(Darwin)
    @Test("Kqueue backend conformance")
    func kqueueEventQueue() throws {
        try Self.validate(KqueueEventQueue.self)
    }
    #endif

    #if os(Linux) || os(Android)
    @Test("Epoll backend conformance")
    func epollEventQueue() throws {
        try Self.validate(EpollEventQueue.self)
    }
    #endif

    static func validate<Queue: EventQueue>(_ queueType: Queue.Type) throws {
        // connected TCP pair on loopback
        let listener = try SocketDescriptor(IPv4Protocol.tcp)
        defer { try? listener.close() }
        try listener.bind(IPv4SocketAddress(address: .loopback, port: 0))
        try listener.listen(backlog: 1)
        let address = try listener.address(IPv4SocketAddress.self)
        let client = try SocketDescriptor(IPv4Protocol.tcp)
        defer { try? client.close() }
        try client.connect(to: address)
        let server = try listener.accept()
        // closed explicitly below to observe end of file, a second close would
        // reap a descriptor number the kernel has since handed to another test
        var isServerClosed = false
        defer { if isServerClosed == false { try? server.close() } }

        var queue = try Queue(maxEvents: 16)
        defer { queue.close() }
        try queue.add(client, events: [.read, .write])

        // connected socket is immediately writable, not readable
        var events = try Self.events(for: client, in: &queue, timeout: 1000)
        #expect(events?.contains(.write) == true)
        #expect(events?.contains(.read) != true)

        // narrow interest mask so write readiness no longer reports
        try queue.update(client, events: [.read])

        // pending data surfaces read readiness
        var byte = UInt8(0x42)
        try withUnsafeBytes(of: &byte) {
            _ = try server.write($0)
        }
        events = try Self.events(for: client, in: &queue, timeout: 1000)
        #expect(events?.contains(.read) == true)
        #expect(events?.contains(.write) != true)

        // level-triggered, readiness persists until drained
        events = try Self.events(for: client, in: &queue, timeout: 0)
        #expect(events?.contains(.read) == true)
        var buffer = Data(count: 1)
        _ = try buffer.withUnsafeMutableBytes {
            try client.read(into: $0)
        }

        // restoring the interest mask reports write readiness again
        try queue.update(client, events: [.read, .write])
        events = try Self.events(for: client, in: &queue, timeout: 1000)
        #expect(events?.contains(.write) == true)
        try queue.update(client, events: [.read])

        // peer close surfaces read readiness for end-of-file
        try server.close()
        isServerClosed = true
        events = try Self.events(for: client, in: &queue, timeout: 1000)
        #expect(events?.contains(.read) == true)

        // removed descriptor no longer reports events
        try queue.remove(client)
        events = try Self.events(for: client, in: &queue, timeout: 0)
        #expect(events == nil)
    }

    private static func events<Queue: EventQueue>(
        for socket: SocketDescriptor,
        in queue: inout Queue,
        timeout: Int
    ) throws -> FileEvents? {
        try queue.wait(timeout: timeout) { buffer in
            buffer.first(where: { $0.fileDescriptor == socket })?.events
        }
    }
}
