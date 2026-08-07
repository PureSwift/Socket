//
//  AncillaryData.swift
//  Socket
//
//  Created by Alsey Coleman Miller.
//

#if os(Linux) || os(Android) || canImport(Darwin)

import Foundation
import SystemPackage

// only the C shims are needed, because the CMSG_* accessors are macros, and unlike the
// other syscall wrappers they are used on Darwin as well as Linux and Android
import CSocket

/// A message received together with any file descriptors that accompanied it.
public struct SocketMessage: Equatable, Hashable, Sendable {

    /// The message payload.
    public let data: Data

    /// File descriptors received as `SCM_RIGHTS` ancillary data.
    ///
    /// - Important: These are owned by the receiver and must be closed when finished with.
    public let fileDescriptors: [SocketDescriptor]

    /// Whether descriptors were discarded because there was no room for them.
    ///
    /// Discarded descriptors are closed rather than leaked.
    public let isTruncated: Bool

    public init(data: Data,
                fileDescriptors: [SocketDescriptor] = [],
                isTruncated: Bool = false) {

        self.data = data
        self.fileDescriptors = fileDescriptors
        self.isTruncated = isTruncated
    }
}

public extension SocketDescriptor {

    /// The maximum number of file descriptors a single message may carry.
    static var maximumAncillaryDescriptors: Int { Int(C_SOCKET_MAX_DESCRIPTORS) }

    /// Send a message carrying file descriptors as `SCM_RIGHTS` ancillary data.
    ///
    /// - Important: At least one byte of payload must be sent. A message with an empty payload
    /// may be discarded before its ancillary data is delivered, silently losing the descriptors.
    ///
    /// - Returns: The number of payload bytes sent.
    @_alwaysEmitIntoClient
    func send<T: DataProtocol>(
        _ data: T,
        fileDescriptors: [SocketDescriptor],
        flags: MessageFlags = []
    ) throws -> Int {

        let bytes = [UInt8](data)

        return try _send(bytes, fileDescriptors: fileDescriptors, flags: flags).get()
    }

    @usableFromInline
    internal func _send(
        _ bytes: [UInt8],
        fileDescriptors: [SocketDescriptor],
        flags: MessageFlags
    ) -> Result<Int, Errno> {

        guard bytes.isEmpty == false
            else { return .failure(.invalidArgument) }

        guard fileDescriptors.count <= SocketDescriptor.maximumAncillaryDescriptors
            else { return .failure(.invalidArgument) }

        let rawDescriptors = fileDescriptors.map { $0.rawValue }

        let result = bytes.withUnsafeBytes { buffer -> CInt in
            rawDescriptors.withUnsafeBufferPointer { descriptors in
                CInt(c_socket_send_descriptors(
                    self.rawValue,
                    buffer.baseAddress,
                    buffer.count,
                    descriptors.baseAddress,
                    descriptors.count,
                    flags.rawValue
                ))
            }
        }

        return result == -1 ? .failure(.current) : .success(Int(result))
    }

    /// Receive a message along with any `SCM_RIGHTS` file descriptors that accompany it.
    ///
    /// - Parameter maximumDescriptors: How many descriptors to accept. Any beyond this are
    /// closed rather than leaked, and the result is marked truncated.
    @_alwaysEmitIntoClient
    func receive(
        _ length: Int,
        maximumDescriptors: Int = SocketDescriptor.maximumAncillaryDescriptors,
        flags: MessageFlags = []
    ) throws -> SocketMessage {

        return try _receive(length, maximumDescriptors: maximumDescriptors, flags: flags).get()
    }

    @usableFromInline
    internal func _receive(
        _ length: Int,
        maximumDescriptors: Int,
        flags: MessageFlags
    ) -> Result<SocketMessage, Errno> {

        guard length > 0
            else { return .failure(.invalidArgument) }

        let capacity = min(max(maximumDescriptors, 0), SocketDescriptor.maximumAncillaryDescriptors)

        var buffer = [UInt8](repeating: 0, count: length)
        var rawDescriptors = [CInt](repeating: -1, count: max(capacity, 1))
        var receivedCount = 0
        var truncated: CInt = 0

        let result = buffer.withUnsafeMutableBytes { bufferPointer -> Int in
            rawDescriptors.withUnsafeMutableBufferPointer { descriptors in
                c_socket_receive_descriptors(
                    self.rawValue,
                    bufferPointer.baseAddress,
                    bufferPointer.count,
                    capacity > 0 ? descriptors.baseAddress : nil,
                    capacity,
                    &receivedCount,
                    &truncated,
                    flags.rawValue
                )
            }
        }

        guard result >= 0
            else { return .failure(.current) }

        let descriptors = rawDescriptors
            .prefix(receivedCount)
            .map { SocketDescriptor(rawValue: $0) }

        let message = SocketMessage(
            data: Data(buffer.prefix(result)),
            fileDescriptors: Array(descriptors),
            isTruncated: truncated != 0
        )

        return .success(message)
    }
}

// MARK: - Socket

public extension Socket {

    /// Send a message carrying file descriptors as `SCM_RIGHTS` ancillary data.
    ///
    /// - Important: At least one byte of payload must be sent; see
    /// ``SystemPackage/SocketDescriptor/send(_:fileDescriptors:flags:)``.
    @discardableResult
    func sendMessage<T: DataProtocol>(
        _ data: T,
        fileDescriptors: [SocketDescriptor]
    ) async throws -> Int {

        return try await manager.sendMessage(data, fileDescriptors: fileDescriptors, for: fileDescriptor)
    }

    /// Receive a message along with any file descriptors that accompany it.
    func receiveMessage(
        _ length: Int,
        maximumDescriptors: Int
    ) async throws -> SocketMessage {

        return try await manager.receiveMessage(length,
                                                maximumDescriptors: maximumDescriptors,
                                                for: fileDescriptor)
    }
}

#endif
