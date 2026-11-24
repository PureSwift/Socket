//
//  LatencyTests.swift
//  Socket
//

#if os(Linux) || os(Android) || canImport(Darwin)

import Foundation
import SystemPackage
import Testing
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

/// Readiness must reach a waiting operation as soon as the kernel reports it,
/// and the monitor must sleep while nothing new happens.
///
/// Part of the serialized ``IdleTests``, so they never run while it measures idle CPU.
extension IdleTests {

    /// The longest a request and its reply may take on average.
    ///
    /// Polling on an interval made every round trip take at least one interval, 100 ms by default.
    static let roundTripBudget = 0.010

    /// The most times the monitor may wake while the sockets under test are quiet.
    ///
    /// A level-triggered condition nothing clears wakes it thousands of times a second.
    /// Other tests run alongside these, so it is not zero.
    static let wakeupBudget = 500

    @Test("Round trips take milliseconds", .timeLimit(.minutes(1)))
    func roundTrip() async throws {
        let (clientDescriptor, serverDescriptor) = try Self.makePair()
        let client = await Socket(fileDescriptor: clientDescriptor)
        let server = await Socket(fileDescriptor: serverDescriptor)
        let count = 100
        let echo = Task {
            for _ in 0 ..< count {
                let request = try await server.read(64)
                try await server.write(request)
            }
        }
        let request = Data("ping".utf8)
        let start = DispatchTime.now()
        for _ in 0 ..< count {
            try await client.write(request)
            let reply = try await client.read(64)
            #expect(reply == request)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        try await echo.value
        let average = elapsed / Double(count)
        print("Round trip: \(String(format: "%.3f", average * 1000)) ms on average over \(count)")
        #expect(average < Self.roundTripBudget, "Round trips took \(average * 1000) ms on average")
        await client.close()
        await server.close()
    }

    @Test("A pending read does not wake the monitor", .timeLimit(.minutes(1)))
    func pendingRead() async throws {
        let (descriptor, peer) = try Self.makePair()
        let socket = await Socket(fileDescriptor: descriptor)
        // data arrives that nobody reads yet
        let byte: [UInt8] = [1]
        _ = byte.withUnsafeBytes { system_write(peer.rawValue, $0.baseAddress, 1) }
        let wakeups = try await Self.wakeups(over: 1.0)
        #expect(wakeups < Self.wakeupBudget, "Monitor woke \(wakeups) times for an unread byte")
        // still delivered once read
        let read = try await socket.read(1)
        #expect(read == Data(byte))
        await socket.close()
        try? peer.close()
    }

    @Test("An unconnected TCP socket does not wake the monitor", .timeLimit(.minutes(1)))
    func unconnectedSocket() async throws {
        // a new TCP socket reports a hangup on Linux whatever it is registered for
        let socket = try await Socket(IPv4Protocol.tcp)
        let wakeups = try await Self.wakeups(over: 1.0)
        #expect(wakeups < Self.wakeupBudget, "Monitor woke \(wakeups) times for an unconnected socket")
        await socket.close()
    }

    @Test("An unconnected TCP socket still connects", .timeLimit(.minutes(1)))
    func connectAfterWaiting() async throws {
        let server = try await Socket(IPv4Protocol.tcp, bind: IPv4SocketAddress(address: .loopback, port: 0))
        try await server.listen()
        let address = try server.fileDescriptor.address(IPv4SocketAddress.self)
        let client = try await Socket(IPv4Protocol.tcp)
        // let the monitor see the new socket's hangup first
        try await Task.sleep(nanoseconds: 200_000_000)
        try await client.connect(to: address)
        let connection = try await server.accept()
        let data = Data("after waiting".utf8)
        try await client.write(data)
        let read = try await connection.read(data.count)
        #expect(read == data)
        await connection.close()
        await client.close()
        await server.close()
    }
}

private extension IdleTests {

    /// A connected pair of Unix stream sockets.
    static func makePair() throws -> (SocketDescriptor, SocketDescriptor) {
        var descriptors: [CInt] = [-1, -1]
        let result = descriptors.withUnsafeMutableBufferPointer { pointer in
            socketpair(
                SocketAddressFamily.unix.rawValue,
                SocketType.stream.rawValue,
                0,
                pointer.baseAddress
            )
        }
        guard result == 0 else {
            throw Errno(rawValue: errno)
        }
        return (SocketDescriptor(rawValue: descriptors[0]), SocketDescriptor(rawValue: descriptors[1]))
    }

    /// How many times the monitor wakes over `seconds`, after letting it settle.
    static func wakeups(over seconds: Double) async throws -> Int {
        try await Task.sleep(nanoseconds: 200_000_000)
        let start = AsyncSocketManager.wakeups.value
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return AsyncSocketManager.wakeups.value - start
    }
}

#endif
