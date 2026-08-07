//
//  AncillaryDataTests.swift
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

/// Tests for `SCM_RIGHTS` file descriptor passing.
///
/// A passed descriptor is a genuinely new descriptor in the receiving process, so the proof is
/// that reading through it observes what the sender wrote through the original.
@Suite(.serialized)
struct AncillaryDataTests {

    /// A connected pair of Unix stream sockets, as `socketpair` provides.
    private func makeSocketPair() throws -> (SocketDescriptor, SocketDescriptor) {

        var descriptors: [CInt] = [-1, -1]

        let result = descriptors.withUnsafeMutableBufferPointer { pointer in
            // the library's own constants, because SOCK_STREAM is an enum on Glibc
            // and a plain CInt on Darwin
            socketpair(
                SocketAddressFamily.unix.rawValue,
                SocketType.stream.rawValue,
                0,
                pointer.baseAddress
            )
        }

        guard result == 0
            else { throw Errno(rawValue: errno) }

        return (SocketDescriptor(rawValue: descriptors[0]),
                SocketDescriptor(rawValue: descriptors[1]))
    }

    /// A temporary file containing `contents`, plus its path.
    private func makeTemporaryFile(contents: String) throws -> (SocketDescriptor, String) {

        let path = "/tmp/socket-scm-test-\(UInt32.random(in: 0 ... .max))"

        try contents.write(toFile: path, atomically: true, encoding: .utf8)

        let descriptor = open(path, O_RDONLY)

        guard descriptor >= 0
            else { throw Errno(rawValue: errno) }

        return (SocketDescriptor(rawValue: descriptor), path)
    }

    private func readAll(_ descriptor: SocketDescriptor) -> String {

        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(descriptor.rawValue, &buffer, buffer.count)

        guard count > 0 else { return "" }

        return String(decoding: buffer[0 ..< count], as: UTF8.self)
    }

    @Test func passesFileDescriptor() throws {

        let (sender, receiver) = try makeSocketPair()
        defer { close(sender.rawValue); close(receiver.rawValue) }

        let (file, path) = try makeTemporaryFile(contents: "payload through a passed descriptor")
        defer { close(file.rawValue); unlink(path) }

        let sent = try sender.send([UInt8]("hello".utf8), fileDescriptors: [file])
        #expect(sent == 5)

        let message = try receiver.receive(64)

        #expect(String(decoding: message.data, as: UTF8.self) == "hello")
        #expect(message.fileDescriptors.count == 1)
        #expect(message.isTruncated == false)

        let received = try #require(message.fileDescriptors.first)
        defer { close(received.rawValue) }

        // A distinct descriptor number in this process, referring to the same open file.
        #expect(received.rawValue != file.rawValue)
        #expect(readAll(received) == "payload through a passed descriptor")
    }

    @Test func passesSeveralFileDescriptors() throws {

        let (sender, receiver) = try makeSocketPair()
        defer { close(sender.rawValue); close(receiver.rawValue) }

        var files = [SocketDescriptor]()
        var paths = [String]()

        for index in 0 ..< 3 {
            let (file, path) = try makeTemporaryFile(contents: "file \(index)")
            files.append(file)
            paths.append(path)
        }

        defer {
            files.forEach { close($0.rawValue) }
            paths.forEach { unlink($0) }
        }

        _ = try sender.send([UInt8]("x".utf8), fileDescriptors: files)

        let message = try receiver.receive(64)
        #expect(message.fileDescriptors.count == 3)

        defer { message.fileDescriptors.forEach { close($0.rawValue) } }

        for (index, descriptor) in message.fileDescriptors.enumerated() {
            #expect(readAll(descriptor) == "file \(index)", "Descriptor order must be preserved")
        }
    }

    @Test func sendsWithoutDescriptors() throws {

        let (sender, receiver) = try makeSocketPair()
        defer { close(sender.rawValue); close(receiver.rawValue) }

        _ = try sender.send([UInt8]("plain".utf8), fileDescriptors: [])

        let message = try receiver.receive(64)

        #expect(String(decoding: message.data, as: UTF8.self) == "plain")
        #expect(message.fileDescriptors.isEmpty)
        #expect(message.isTruncated == false)
    }

    /// Descriptors that do not fit must be closed rather than leaked, and reported.
    @Test func closesDescriptorsThatDoNotFit() throws {

        let (sender, receiver) = try makeSocketPair()
        defer { close(sender.rawValue); close(receiver.rawValue) }

        var files = [SocketDescriptor]()
        var paths = [String]()

        for index in 0 ..< 3 {
            let (file, path) = try makeTemporaryFile(contents: "file \(index)")
            files.append(file)
            paths.append(path)
        }

        defer {
            files.forEach { close($0.rawValue) }
            paths.forEach { unlink($0) }
        }

        _ = try sender.send([UInt8]("x".utf8), fileDescriptors: files)

        // Accept only one of the three.
        let message = try receiver.receive(64, maximumDescriptors: 1)

        #expect(message.fileDescriptors.count == 1)
        #expect(message.isTruncated, "The caller must be told descriptors were dropped")

        defer { message.fileDescriptors.forEach { close($0.rawValue) } }

        #expect(readAll(message.fileDescriptors[0]) == "file 0")
    }

    @Test func acceptsNoDescriptors() throws {

        let (sender, receiver) = try makeSocketPair()
        defer { close(sender.rawValue); close(receiver.rawValue) }

        let (file, path) = try makeTemporaryFile(contents: "unwanted")
        defer { close(file.rawValue); unlink(path) }

        _ = try sender.send([UInt8]("x".utf8), fileDescriptors: [file])

        let message = try receiver.receive(64, maximumDescriptors: 0)

        #expect(message.fileDescriptors.isEmpty)
        #expect(message.isTruncated)
    }

    /// An empty payload may be discarded before its ancillary data is seen, so it is rejected.
    @Test func rejectsEmptyPayload() throws {

        let (sender, receiver) = try makeSocketPair()
        defer { close(sender.rawValue); close(receiver.rawValue) }

        let (file, path) = try makeTemporaryFile(contents: "x")
        defer { close(file.rawValue); unlink(path) }

        #expect(throws: Errno.invalidArgument) {
            try sender.send([UInt8](), fileDescriptors: [file])
        }
    }

    @Test func rejectsTooManyDescriptors() throws {

        let (sender, receiver) = try makeSocketPair()
        defer { close(sender.rawValue); close(receiver.rawValue) }

        let (file, path) = try makeTemporaryFile(contents: "x")
        defer { close(file.rawValue); unlink(path) }

        let tooMany = [SocketDescriptor](
            repeating: file,
            count: SocketDescriptor.maximumAncillaryDescriptors + 1
        )

        #expect(throws: Errno.invalidArgument) {
            try sender.send([UInt8]("x".utf8), fileDescriptors: tooMany)
        }
    }

    /// The same exchange through the async `Socket` API rather than the raw descriptor.
    @Test func passesThroughAsyncSocket() async throws {

        let (senderDescriptor, receiverDescriptor) = try makeSocketPair()

        let sender = await Socket(fileDescriptor: senderDescriptor)
        let receiver = await Socket(fileDescriptor: receiverDescriptor)

        let (file, path) = try makeTemporaryFile(contents: "through the async api")
        defer { close(file.rawValue); unlink(path) }

        _ = try await sender.sendMessage([UInt8]("hi".utf8), fileDescriptors: [file])

        let message = try await receiver.receiveMessage(64, maximumDescriptors: 4)

        #expect(String(decoding: message.data, as: UTF8.self) == "hi")
        #expect(message.fileDescriptors.count == 1)

        if let received = message.fileDescriptors.first {
            #expect(readAll(received) == "through the async api")
            close(received.rawValue)
        }

        await sender.close()
        await receiver.close()
    }
}

#endif
