import Foundation
import Testing
import SystemPackage
@testable import Socket

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

/// Idle sockets must not keep the monitor busy.
///
/// A connected socket is almost always writable, so registering for write readiness
/// unconditionally makes every wait return every socket on every tick.
@Suite("Idle Tests", .serialized)
struct IdleTests {

    /// Microseconds of CPU allowed per socket per second while idle.
    ///
    /// Measured at ~2 with on demand write readiness and ~88 with a standing
    /// registration, so this fails long before the old behavior returns.
    static let budget = 20.0

    static let duration = 5.0

    @Test("Idle sockets report no events")
    func idleSocketsReportNoEvents() throws {
        let pairs = try SocketPairs(count: 8)
        defer { pairs.close() }
        var queue = try PlatformEventQueue(maxEvents: 64)
        defer { queue.close() }
        // exactly what the manager registers, write readiness is added on demand
        for socket in pairs.sockets {
            try queue.add(socket, events: AsyncSocketManager.monitoredEvents)
        }
        let ready = try queue.wait(timeout: 0) { $0.map(\.fileDescriptor) }
        #expect(ready.isEmpty, "Idle sockets reported \(ready.count) events")
    }

    @Test("Idle CPU stays within budget")
    func idleCPU() async throws {
        let pairs = try SocketPairs(count: Self.socketPairCount)
        var sockets = [Socket]()
        for fileDescriptor in pairs.sockets {
            sockets.append(await Socket(fileDescriptor: fileDescriptor))
        }

        // let registration settle before measuring
        try await Task.sleep(nanoseconds: 500_000_000)

        let start = Self.cpuSeconds()
        try await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
        let elapsed = Self.cpuSeconds() - start

        let perSocketSecond = elapsed / (Double(sockets.count) * Self.duration) * 1_000_000
        print("Idle CPU: \(String(format: "%.3f", elapsed))s for \(sockets.count) sockets, \(String(format: "%.1f", perSocketSecond))µs per socket second")
        #expect(
            perSocketSecond < Self.budget,
            "Idle CPU \(perSocketSecond)µs per socket second exceeds budget of \(Self.budget)µs"
        )

        // close before returning so the next test starts from a clean table
        for socket in sockets {
            await socket.close()
        }
        pairs.closeListener()
    }

    /// Sized to stay well inside the open file limit.
    static let socketPairCount = 100

    static func cpuSeconds() -> Double {
        var usage = rusage()
        #if canImport(Glibc)
        // Glibc imports the constant as an enum
        getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
        #else
        getrusage(RUSAGE_SELF, &usage)
        #endif
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}

/// Connected loopback socket pairs.
private struct SocketPairs: ~Copyable {

    let listener: SocketDescriptor

    let sockets: [SocketDescriptor]

    init(count: Int) throws {
        let listener = try SocketDescriptor(IPv4Protocol.tcp)
        try listener.bind(IPv4SocketAddress(address: .loopback, port: 0))
        try listener.listen(backlog: count)
        let address = try listener.address(IPv4SocketAddress.self)
        var sockets = [SocketDescriptor]()
        sockets.reserveCapacity(count * 2)
        for _ in 0 ..< count {
            let client = try SocketDescriptor(IPv4Protocol.tcp)
            try client.connect(to: address)
            sockets.append(client)
            sockets.append(try listener.accept())
        }
        self.listener = listener
        self.sockets = sockets
    }

    func closeListener() {
        try? listener.close()
    }

    func close() {
        sockets.forEach { try? $0.close() }
        closeListener()
    }
}
