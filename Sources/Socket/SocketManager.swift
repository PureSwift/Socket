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
        // Add to runloop of background thread from concurrency thread pool
        Task(priority: .medium) { [weak self] in
            while let self = self {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    try await self.poll()
                }
                catch {
                    assertionFailure("\(error)")
                }
            }
        }
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
        // append socket
        sockets[fileDescriptor] = SocketState(
            fileDescriptor: fileDescriptor,
            event: event
        )
        updatePollDescriptors()
        startMonitoring()
    }
    
    func remove(_ fileDescriptor: FileDescriptor, error: Error? = nil) {
        guard let socket = sockets[fileDescriptor] else {
            return // could have been removed by `poll()`
        }
        // update sockets to monitor
        sockets[fileDescriptor] = nil
        updatePollDescriptors()
        // close actual socket
        try? fileDescriptor.close()
        // notify
        socket.event?(.close(error))
    }
    
    @discardableResult
    internal func write(_ data: Data, for fileDescriptor: FileDescriptor) async throws -> Int {
        guard let socket = sockets[fileDescriptor] else {
            assertionFailure("Unknown socket")
            throw Errno.invalidArgument
        }
        try await wait(for: .write, fileDescriptor: fileDescriptor)
        return try await socket.write(data: data)
    }
    
    internal func read(_ length: Int, for fileDescriptor: FileDescriptor) async throws -> Data {
        guard let socket = sockets[fileDescriptor] else {
            assertionFailure("Unknown socket")
            throw Errno.invalidArgument
        }
        try await wait(for: .read, fileDescriptor: fileDescriptor)
        return try await socket.read(length: length)
    }
    
    internal func events(for fileDescriptor: FileDescriptor) -> FileEvents {
        guard let poll = pollDescriptors.first(where: { $0.fileDescriptor == fileDescriptor }) else {
            assertionFailure()
            return []
        }
        return poll.returnedEvents
    }
    
    private func wait(
        for event: FileEvents,
        fileDescriptor: FileDescriptor,
        sleep nanoseconds: UInt64 = 10_000_000
    ) async throws {
        while events(for: fileDescriptor).contains(event) == false {
            try Task.checkCancellation()
            try await self.poll()
            if events(for: fileDescriptor).contains(event) == false {
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }
    
    private func updatePollDescriptors() {
        pollDescriptors = sockets.keys
            .lazy
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { FileDescriptor.Poll(fileDescriptor: $0, events: .socket) }
    }
    
    internal func poll() async throws {
        guard pollDescriptors.isEmpty == false
            else { return }
        do {
            try pollDescriptors.poll()
        }
        catch {
            log("Unable to poll for events. \(error.localizedDescription)")
            throw error
        }
        
        for poll in pollDescriptors {
            let fileEvents = poll.returnedEvents
            let fileDescriptor = poll.fileDescriptor
            if fileEvents.contains(.read) {
                await shouldRead(fileDescriptor)
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
        guard let _ = self.sockets[fileDescriptor] else {
            assertionFailure()
            return
        }
        self.remove(fileDescriptor, error: error)
    }
    
    private func shouldRead(_ fileDescriptor: FileDescriptor) async {
        guard let socket = self.sockets[fileDescriptor] else {
            assertionFailure()
            return
        }
        // notify
        socket.event?(.pendingRead)
    }
}

// MARK: - Supporting Types

extension SocketManager {
    
    actor SocketState {
        
        let fileDescriptor: FileDescriptor
                
        let event: ((Socket.Event) -> ())?
        
        var isExecuting = false
        
        init(fileDescriptor: FileDescriptor,
             event: ((Socket.Event) -> ())? = nil
        ) {
            self.fileDescriptor = fileDescriptor
            self.event = event
        }
    }
}

extension SocketManager.SocketState {
    
    // locks the socket
    private func execute() {
        
    }
    
    func write(data: Data) throws -> Int {
        assert(isExecuting == false)
        log("Will write \(data.count) bytes to \(fileDescriptor)")
        isExecuting = true
        defer { isExecuting = false }
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.write($0)
        }
        // notify
        event?(.write(byteCount))
        return byteCount
    }
    
    func read(length: Int) throws -> Data {
        assert(isExecuting == false)
        log("Will read \(length) bytes to \(fileDescriptor)")
        isExecuting = true
        defer { isExecuting = false }
        var data = Data(count: length)
        let bytesRead = try data.withUnsafeMutableBytes {
            try fileDescriptor.read(into: $0)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        // notify
        event?(.read(bytesRead))
        return data
    }
}
