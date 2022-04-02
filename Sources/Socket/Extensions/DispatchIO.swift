//
//  DispatchIO.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import Dispatch
import SystemPackage

internal extension DispatchIO {
    
    /// Creates a new I/O channel that accesses the specified file descriptor.
    ///
    /// - Returns: The newly created DispatchIO object configured with the specified information.
    ///
    /// The channel takes control of the specified file descriptor until the channel closes,
    /// either deliberately on your part or because an error occurred. While the channel
    /// owns the file descriptor, the system modifies flags such as `O_NONBLOCK`
    /// automatically. It is a programmer error for you to modify the file descriptor while
    /// the channel owns it. However, you may create additional channels based on the
    /// same file descriptor.
    static func open(stream fileDescriptor: Int32, queue: DispatchQueue) async throws -> DispatchIO {
        return try await withCheckedThrowingContinuation { continuation in
            var dispatchIO: DispatchIO!
            dispatchIO = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: queue, cleanupHandler: { errno in
                if errno == 0 {
                    continuation.resume(returning: dispatchIO)
                } else {
                    continuation.resume(throwing: Errno(rawValue: errno))
                }
            })
        }
    }
    
    /// This function reads the specified data.
    func read(offset: Int64 = 0, length: Int64, queue: DispatchQueue) -> AsyncThrowingStream<DispatchData, Error> {
        return AsyncThrowingStream<DispatchData, Error>(DispatchData.self, bufferingPolicy: .unbounded) { continuation in
            read(offset: offset, length: numericCast(length), queue: queue) { done, data, errno in
                guard errno == 0 else {
                    continuation.finish(throwing: Errno(rawValue: errno))
                    return
                }
                if let data = data {
                    continuation.yield(data)
                }
                if done {
                    continuation.finish()
                }
            }
        }
    }
    
    /// Schedules an asynchronous write operation for the specified channel.
    func write(offset: Int64 = 0, data: DispatchData, queue: DispatchQueue) -> AsyncThrowingStream<DispatchData, Error> {
        return AsyncThrowingStream<DispatchData, Error>(DispatchData.self, bufferingPolicy: .unbounded) { continuation in
            write(offset: offset, data: data, queue: queue) { done, data, error in
                guard errno == 0 else {
                    continuation.finish(throwing: Errno(rawValue: errno))
                    return
                }
                if let data = data {
                    continuation.yield(data)
                }
                if done {
                    continuation.finish()
                }
            }
        }
    }
}
