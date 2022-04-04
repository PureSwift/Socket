//
//  SocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage

/// Socket Manager
internal actor SocketManager {
    
    static let shared = SocketManager()
    
    private var sockets = [FileDescriptor: SocketState]()
    
    private var pollDescriptors = [FileDescriptor.Poll]()
    
    private var isMonitoring = false
    
    private init() { }
    
    private func startMonitoring() {
        guard isMonitoring == false else { return }
        isMonitoring = true
        
    }
    
    func contains(_ fileDescriptor: FileDescriptor) -> Bool {
        return sockets.keys.contains(fileDescriptor)
    }
    
    func add(
        fileDescriptor: FileDescriptor,
        event: ((Socket.Event) -> ())? = nil
    ) {
        guard sockets.keys.contains(fileDescriptor) == false else {
            assertionFailure("Another socket already exists")
            return
        }
        // append lock
        sockets[fileDescriptor] = SocketState(
            fileDescriptor: fileDescriptor,
            event: event
        )
        updatePollDescriptors()
        startMonitoring()
    }
    
    func remove(_ fileDescriptor: FileDescriptor) {
        guard let socket = sockets[fileDescriptor] else {
            return // could have been removed by `poll()`
        }
        try? fileDescriptor.close() // TODO:
        sockets[fileDescriptor] = nil
        updatePollDescriptors()
    }
    
    @discardableResult
    func write(_ data: Data, for fileDescriptor: FileDescriptor) async throws -> Int {
        guard let socket = sockets[fileDescriptor] else {
            fatalError("Unknown socket")
        }
        let id = await socket.newID()
        //checkCancellation()
        return try await withThrowingContinuation(for: fileDescriptor) { continuation in
            let write = Write(
                id: id,
                data: data,
                continuation: continuation
            )
            Task(priority: .high) { [unowned self] in
                // queue write
                await socket.queue(write)
                // poll immediately, write as soon as possible
                await self.poll()
            }
        }
    }
    
    func read(_ length: Int, for fileDescriptor: FileDescriptor) async throws -> Data {
        guard let socket = sockets[fileDescriptor] else {
            fatalError("Unknown socket")
        }
        let id = await socket.newID()
        //checkCancellation()
        return try await withThrowingContinuation(for: fileDescriptor) { continuation in
            let read = Read(
                id: id,
                length: length,
                continuation: continuation
            )
            Task(priority: .high) { [unowned self] in
                // queue write
                await socket.queue(read)
                // poll immediately, write as soon as possible
                await self.poll()
            }
        }
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
    
    internal func poll() async {
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
                await shouldRead(fileDescriptor)
            }
            if fileEvents.contains(.write) {
                await canWrite(fileDescriptor)
            }
            if fileEvents.contains(.invalidRequest) {
                assertionFailure()
                await error(.badFileDescriptor, for: fileDescriptor)
            }
            if fileEvents.contains(.hangup) {
                await error(.connectionAbort, for: fileDescriptor)
            }
            if fileEvents.contains(.error) {
                await error(.connectionReset, for: fileDescriptor)
            }
        }
    }
    
    private func error(_ error: Errno, for fileDescriptor: FileDescriptor) async {
        guard let socket = self.sockets[fileDescriptor] else {
            assertionFailure()
            return
        }
        // end all pending operations
        while let operation = await socket.dequeueRead() {
            operation.continuation.resume(throwing: error)
        }
        while let operation = await socket.dequeueWrite() {
            operation.continuation.resume(throwing: error)
        }
        self.remove(fileDescriptor)
    }
    
    private func shouldRead(_ fileDescriptor: FileDescriptor) async {
        guard let socket = self.sockets[fileDescriptor] else {
            assertionFailure()
            return
        }
        guard let read = await socket.dequeueRead()
            else { return }
        await socket.execute(read)
    }
    
    private func canWrite(_ fileDescriptor: FileDescriptor) async {
        guard let socket = self.sockets[fileDescriptor] else {
            assertionFailure()
            return
        }
        guard let write = await socket.dequeueWrite()
            else { return }
        // execute
        await socket.execute(write)
    }
}

// MARK: - Supporting Types

extension SocketManager {
    
    actor SocketState {
        
        let fileDescriptor: FileDescriptor
                
        let event: ((Socket.Event) -> ())?
        
        init(fileDescriptor: FileDescriptor,
             event: ((Socket.Event) -> ())?) {
            self.fileDescriptor = fileDescriptor
            self.event = event
        }
        
        var isExecuting = false
        
        var pendingWrite = Queue<Write>()
        
        var pendingRead = Queue<Read>()
        
        private var lastID: UInt64 = 0
    }
}

internal extension SocketManager.SocketState {
    
    func newID() -> UInt64 {
        let (newValue, overflow) = lastID.addingReportingOverflow(1)
        lastID = overflow ? 0 : newValue
        return lastID
    }
    
    func queue(_ write: SocketManager.Write) {
        pendingWrite.push(write)
    }
    
    func dequeueWrite() -> SocketManager.Write? {
        return pendingWrite.pop()
    }
    
    func queue(_ read: SocketManager.Read) {
        pendingRead.push(read)
    }
    
    func dequeueRead() -> SocketManager.Read? {
        return pendingRead.pop()
    }
}

internal extension SocketManager {
    
    struct Write {
        let id: UInt64
        let data: Data
        let continuation: SocketContinuation<Int, Error>
    }
    
    struct Read {
        let id: UInt64
        let length: Int
        let continuation: SocketContinuation<Data, Error>
    }
}

extension SocketManager.SocketState {
    
    func execute(_ operation: SocketManager.Write) {
        assert(isExecuting == false)
        log("Will write \(operation.data.count) bytes to \(fileDescriptor)")
        isExecuting = true
        defer { isExecuting = false }
        do {
            let byteCount = try operation.data.withUnsafeBytes {
                try fileDescriptor.write($0)
            }
            operation.continuation.resume(returning: byteCount)
        }
        catch {
            operation.continuation.resume(throwing: error)
        }
    }
    
    func execute(_ operation: SocketManager.Read) {
        assert(isExecuting == false)
        log("Will read \(operation.length) bytes to \(fileDescriptor)")
        isExecuting = true
        defer { isExecuting = false }
        var data = Data(count: operation.length)
        do {
            let bytesRead = try data.withUnsafeMutableBytes {
                try fileDescriptor.read(into: $0)
            }
            if bytesRead < operation.length {
                data = data.prefix(bytesRead)
            }
            operation.continuation.resume(returning: data)
        } catch {
            operation.continuation.resume(throwing: error)
        }
    }
}
