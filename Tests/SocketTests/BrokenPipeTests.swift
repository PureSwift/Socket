//
//  BrokenPipeTests.swift
//  Socket
//

#if os(Linux) || os(Android) || canImport(Darwin)

import Foundation
import SystemPackage
import Testing
@testable import Socket

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// How many times `SIGPIPE` reached the handler `countingPipeSignals` installs.
nonisolated(unsafe) private var pipeSignals = 0

/// Sending to a peer that has closed must fail with `brokenPipe`, and raise no `SIGPIPE`.
///
/// The signal is counted by a handler of the test's own, so the bug fails a test
/// wherever it runs, rather than ending the process as `SIGPIPE`'s default action does.
@Suite(.serialized)
struct BrokenPipeTests {

    /// Runs `body` with a handler that counts `SIGPIPE`, then expects none.
    private func countingPipeSignals(_ body: () async throws -> Void) async rethrows {

        pipeSignals = 0
        let previous = signal(SIGPIPE) { _ in pipeSignals += 1 }
        defer { signal(SIGPIPE, previous) }

        try await body()

        #expect(pipeSignals == 0)
    }

    /// A Unix stream socket whose peer has already closed.
    private func makeOrphanedSocket() async throws -> Socket {

        var descriptors: [CInt] = [-1, -1]

        let result = descriptors.withUnsafeMutableBufferPointer { pointer in
            socketpair(
                SocketAddressFamily.unix.rawValue,
                SocketType.stream.rawValue,
                0,
                pointer.baseAddress
            )
        }

        guard result == 0
            else { throw Errno(rawValue: errno) }

        close(descriptors[1])

        return await Socket(fileDescriptor: SocketDescriptor(rawValue: descriptors[0]))
    }

    @Test func writeFailsWithBrokenPipe() async throws {

        let socket = try await makeOrphanedSocket()

        await countingPipeSignals {
            await #expect(throws: Errno.brokenPipe) {
                try await socket.write(Data("after the peer closed".utf8))
            }
        }

        await socket.close()
    }

    @Test func sendMessageFailsWithBrokenPipe() async throws {

        let socket = try await makeOrphanedSocket()

        await countingPipeSignals {
            await #expect(throws: Errno.brokenPipe) {
                try await socket.sendMessage(Data("after the peer closed".utf8))
            }
        }

        await socket.close()
    }

    @Test func sendFileDescriptorsFailsWithBrokenPipe() async throws {

        let socket = try await makeOrphanedSocket()

        await countingPipeSignals {
            await #expect(throws: Errno.brokenPipe) {
                try await socket.sendMessage([UInt8]("hi".utf8), fileDescriptors: [SocketDescriptor(rawValue: 0)])
            }
        }

        await socket.close()
    }
}

#endif
