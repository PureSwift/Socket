//
//  PeripheralContinuation.wift
//  
//
//  Created by Alsey Coleman Miller on 20/12/21.
//

import Foundation
import SystemPackage

#if DEBUG
internal struct SocketContinuation<T, E> where E: Error {
    
    private let function: String
    
    private let continuation: CheckedContinuation<T, E>
    
    private let fileDescriptor: FileDescriptor
    
    fileprivate init(
        continuation: UnsafeContinuation<T, E>,
        function: String,
        fileDescriptor: FileDescriptor
    ) {
        self.continuation = CheckedContinuation(continuation: continuation, function: function)
        self.function = function
        self.fileDescriptor = fileDescriptor
    }
    
    func resume(
        returning value: T,
        function: String = #function
    ) {
        continuation.resume(returning: value)
    }
    
    func resume(
        throwing error: E,
        function: String = #function
    ) {
        continuation.resume(throwing: error)
    }
}

extension SocketContinuation where T == Void {
    
    func resume(function: String = #function) {
        self.resume(returning: (), function: function)
    }
}

internal func withContinuation<T>(
    for fileDescriptor: FileDescriptor,
    function: String = #function,
    _ body: (SocketContinuation<T, Never>) -> Void
) async -> T {
    return await withUnsafeContinuation {
        body(SocketContinuation(continuation: $0, function: function, fileDescriptor: fileDescriptor))
    }
}

internal func withThrowingContinuation<T>(
    for fileDescriptor: FileDescriptor,
    function: String = #function,
    _ body: (SocketContinuation<T, Swift.Error>) -> Void
) async throws -> T {
    return try await withUnsafeThrowingContinuation {
        body(SocketContinuation(continuation: $0, function: function, fileDescriptor: fileDescriptor))
    }
}
#else
internal typealias SocketContinuation<T, E> = CheckedContinuation<T, E> where E: Error

@inline(__always)
internal func withContinuation<T>(
    for fileDescriptor: FileDescriptor,
    function: String = #function,
    _ body: (UnsafeContinuation<T, Never>) -> Void
) async -> T {
    return await withUnsafeContinuation(body)
}

@inline(__always)
internal func withThrowingContinuation<T>(
    for fileDescriptor: FileDescriptor,
    function: String = #function,
    _ body: (UnsafeContinuation<T, Swift.Error>) -> Void
) async throws -> T {
    return try await withUnsafeThrowingContinuation(body)
}
#endif
