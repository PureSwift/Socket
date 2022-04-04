//
//  SocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage

/// Socket Manager
internal final class SocketManager {
    
    static let shared = SocketManager()
        
    private var didSetup = false
    
    private var sockets = [FileDescriptor: SocketState]()
    
    private var pollDescriptors = [FileDescriptor.Poll]()
            
    private var lock = NSLock()
    
    private var lastID: UInt64 = 0
    
    private init() {
        // Add to runloop of background thread from concurrency thread pool
        Task(priority: .medium) { [weak self] in
            while let self = self {
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.poll()
            }
        }
    }
    
    func contains(_ fileDescriptor: FileDescriptor) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sockets.keys.contains(fileDescriptor)
    }
    
    func add(_ fileDescriptor: FileDescriptor) {
        // append lock
        lock.lock()
        if sockets[fileDescriptor] == nil {
            sockets[fileDescriptor] = SocketState(
                fileDescriptor: fileDescriptor
            )
        }
        updatePollDescriptors()
        lock.unlock()
    }
    
    func remove(_ fileDescriptor: FileDescriptor) {
        try? fileDescriptor.close()
        lock.lock()
        sockets[fileDescriptor] = nil
        updatePollDescriptors()
        lock.unlock()
    }
    
    @discardableResult
    func write(_ data: Data, for fileDescriptor: FileDescriptor) async throws -> Int {
        return try await withThrowingContinuation(for: fileDescriptor) { continuation in
            let write = Write(
                id: newID(),
                fileDescriptor: fileDescriptor,
                data: data,
                continuation: continuation
            )
            // queue write
            lock.lock()
            assert(sockets[fileDescriptor] != nil)
            sockets[fileDescriptor]?.pendingWrite.push(write)
            lock.unlock()
            // poll immediately, write as soon as possible
            Task(priority: .high) { [unowned self] in
                self.poll()
            }
        }
    }
    
    func read(_ length: Int, for fileDescriptor: FileDescriptor) async throws -> Data {
        return try await withThrowingContinuation(for: fileDescriptor) { continuation in
            let read = Read(
                id: newID(),
                fileDescriptor: fileDescriptor,
                length: length,
                continuation: continuation
            )
            // queue read
            lock.lock()
            assert(sockets[fileDescriptor] != nil)
            sockets[fileDescriptor]?.pendingRead.push(read)
            lock.unlock()
            // poll immediately, small transfers can benefit
            Task(priority: .high) { [unowned self] in
                self.poll()
            }
            
        }
    }
    
    private func newID() -> UInt64 {
        let (newValue, overflow) = lastID.addingReportingOverflow(1)
        lastID = overflow ? 0 : newValue
        return lastID
    }
    
    private func checkCancellation() {
        // watch for task cancellation
        Task(priority: .medium) {
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            try Task.checkCancellation()
        }
    }
    
    private func updatePollDescriptors() {
        pollDescriptors = sockets.keys
            .lazy
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { FileDescriptor.Poll(fileDescriptor: $0, events: .socket) }
    }
    
    internal func poll() {
        lock.lock()
        defer { lock.unlock() }
        guard pollDescriptors.isEmpty == false
            else { return }
        do {
            try pollDescriptors.poll()
        }
        catch {
            log("Unable to poll for events. \(error.localizedDescription)")
            return
        }
        
        for poll in pollDescriptors {
            let fileEvents = poll.returnedEvents
            let fileDescriptor = poll.fileDescriptor
            if fileEvents.contains(.read) ||
                fileEvents.contains(.readUrgent) {
                shouldRead(fileDescriptor)
            }
            if fileEvents.contains(.write) {
                canWrite(fileDescriptor)
            }
            if fileEvents.contains(.invalidRequest) {
                assertionFailure()
                error(.badFileDescriptor, for: fileDescriptor)
            }
            if fileEvents.contains(.hangup) {
                error(.connectionAbort, for: fileDescriptor)
            }
            if fileEvents.contains(.error) {
                error(.connectionReset, for: fileDescriptor)
            }
        }
    }
    
    private func error(_ error: Errno, for fileDescriptor: FileDescriptor) {
        guard let socket = self.sockets[fileDescriptor] else {
            assertionFailure()
            return
        }
        // execute
        Task(priority: .high) { [unowned self] in
            // end all pending operations
            socket.lock.lock()
            while let operation = socket.pendingRead.pop() {
                operation.continuation.resume(throwing: error)
            }
            while let operation = socket.pendingWrite.pop() {
                operation.continuation.resume(throwing: error)
            }
            socket.lock.unlock()
            self.remove(fileDescriptor)
        }
    }
    
    private func shouldRead(_ fileDescriptor: FileDescriptor) {
        guard let socket = self.sockets[fileDescriptor],
              let read = socket.pendingRead.pop()
            else { return }
        // execute
        Task(priority: .high) {
            socket.lock.lock()
            read.execute()
            socket.lock.unlock()
        }
    }
    
    private func canWrite(_ fileDescriptor: FileDescriptor) {
        guard let socket = self.sockets[fileDescriptor],
              let write = socket.pendingWrite.pop()
            else { return }
        // execute
        Task(priority: .high) {
            socket.lock.lock()
            write.execute()
            socket.lock.unlock()
        }
    }
}

// MARK: - Supporting Types

extension SocketManager {
    
    final class SocketState {
        
        let fileDescriptor: FileDescriptor
        
        init(fileDescriptor: FileDescriptor) {
            self.fileDescriptor = fileDescriptor
        }
        
        let lock = NSLock()
        
        var pendingWrite = Queue<Write>()
        
        var pendingRead = Queue<Read>()
    }
}

internal extension SocketManager {
    
    struct Write {
        let id: UInt64
        let fileDescriptor: FileDescriptor
        let data: Data
        let continuation: SocketContinuation<Int, Error>
        
        func execute() {
            log("Will write \(data.count) bytes to \(fileDescriptor)")
            
            do {
                let byteCount = try data.withUnsafeBytes {
                    try fileDescriptor.write($0)
                }
                continuation.resume(returning: byteCount)
            }
            catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    struct Read {
        let id: UInt64
        let fileDescriptor: FileDescriptor
        let length: Int
        let continuation: SocketContinuation<Data, Error>
        
        func execute() {
            log("Will read \(length) bytes to \(fileDescriptor)")
            var data = Data(count: length)
            do {
                let bytesRead = try data.withUnsafeMutableBytes {
                    try fileDescriptor.read(into: $0)
                }
                if bytesRead < length {
                    data = data.prefix(bytesRead)
                }
                continuation.resume(returning: data)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - C Callbacks

@_silgen_name("swift_socket_manager_perform")
internal func SocketManagerPerform(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer = pointer else {
        assertionFailure()
        return
    }
    let manager = Unmanaged<SocketManager>
        .fromOpaque(pointer)
        .takeUnretainedValue()
    manager.poll()
}
