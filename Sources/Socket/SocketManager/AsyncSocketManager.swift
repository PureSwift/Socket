//
//  AsyncSocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/12/23.
//

import Foundation

public struct AsyncSocketManagerConfiguration {
    
    /// Log
    public var log: ((String) -> ())?
    
    /// Task priority for backgroud socket polling.
    public var monitorPriority: TaskPriority
    
    /// Interval in nanoseconds for monitoring / polling socket.
    public var monitorInterval: UInt64
    
    public init(
        log: ((String) -> ())? = nil,
        monitorPriority: TaskPriority = .medium,
        monitorInterval: UInt64 = 100_000_000
    ) {
        self.log = log
        self.monitorPriority = monitorPriority
        self.monitorInterval = monitorInterval
    }
}

extension AsyncSocketManagerConfiguration: SocketManagerConfiguration {
    
    public var manager: some SocketManager {
        let manager = AsyncSocketManager.shared
        manager.configuration = self
        return manager
    }
}

/// Async Socket Manager
internal final class AsyncSocketManager: SocketManager {
    
    // MARK: - Properties
    
    public var configuration = AsyncSocketManagerConfiguration()
    
    private let storage = Storage()
    
    // MARK: - Initialization
    
    static let shared = AsyncSocketManager()
    
    private init() { }
    
    // MARK: - Methods
    
    func startMonitoring() async {
        guard await storage.update({
            guard $0.isMonitoring == false else { return false }
            log("Will start monitoring")
            $0.isMonitoring = true
            return true
        }) else { return }
        // Create top level task to monitor
        Task.detached(priority: configuration.monitorPriority) { [unowned self] in
            while await self.isMonitoring {
                do {
                    let hasEvents = try await storage.update({ (state: inout ManagerState) -> Bool in
                        // poll
                        let hasEvents = try state.poll()
                        // stop monitoring if no sockets
                        if state.pollDescriptors.isEmpty {
                            state.isMonitoring = false
                        }
                        return hasEvents
                    })
                    if hasEvents == false {
                        try await Task.sleep(nanoseconds: configuration.monitorInterval)
                    }
                }
                catch {
                    log("Socket monitoring failed. \(error.localizedDescription)")
                    assertionFailure("Socket monitoring failed. \(error.localizedDescription)")
                    await storage.update {
                        $0.isMonitoring = false
                    }
                }
            }
        }
    }
    
    func contains(_ fileDescriptor: SocketDescriptor) async -> Bool {
        return await sockets.keys.contains(fileDescriptor)
    }
    
    func add(
        _ fileDescriptor: SocketDescriptor
    ) async -> Socket.Event.Stream {
        guard await sockets.keys.contains(fileDescriptor) == false else {
            fatalError("Another socket for file descriptor \(fileDescriptor) already exists.")
        }
        log("Add socket \(fileDescriptor)")
        // make sure its non blocking
        do {
            var status = try fileDescriptor.getStatus()
            if status.contains(.nonBlocking) == false {
                status.insert(.nonBlocking)
                try fileDescriptor.setStatus(status)
            }
        }
        catch {
            log("Unable to set non blocking. \(error)")
            assertionFailure("Unable to set non blocking. \(error)")
        }
        // append socket with events continuation
        let eventStream = await storage.update { manager in
            Socket.Event.Stream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                manager.sockets[fileDescriptor] = SocketState(
                    fileDescriptor: fileDescriptor,
                    event: continuation
                )
            }
        }
        // start monitoring
        await startMonitoring()
        return eventStream
    }
    
    func remove(_ fileDescriptor: SocketDescriptor, error: Error? = nil) async {
        await storage.update {
            $0.remove(fileDescriptor, error: error)
        }
    }
    
    @discardableResult
    func write(_ data: Data, for fileDescriptor: SocketDescriptor) async throws -> Int {
        try await wait(for: .write, fileDescriptor: fileDescriptor) {
            try $0.write(data)
        }
            
    }
    
    @discardableResult
    func sendMessage(_ data: Data, for fileDescriptor: SocketDescriptor) async throws -> Int {
        try await wait(for: .write, fileDescriptor: fileDescriptor) {
            try $0.sendMessage(data)
        }
    }
    
    @discardableResult
    func sendMessage<Address: SocketAddress>(_ data: Data, to address: Address,  for fileDescriptor: SocketDescriptor) async throws -> Int {
        try await wait(for: .write, fileDescriptor: fileDescriptor) {
            try $0.sendMessage(data, to: address)
        }
    }
    
    func read(_ length: Int, for fileDescriptor: SocketDescriptor) async throws -> Data {
        try await wait(for: .read, fileDescriptor: fileDescriptor) {
            try $0.read(length)
        }
    }
    
    func receiveMessage(_ length: Int, for fileDescriptor: SocketDescriptor) async throws -> Data {
        try await wait(for: .read, fileDescriptor: fileDescriptor) {
            try $0.receiveMessage(length)
        }
    }
    
    func receiveMessage<Address: SocketAddress>(_ length: Int, fromAddressOf addressType: Address.Type = Address.self, for fileDescriptor: SocketDescriptor) async throws -> (Data, Address) {
        try await wait(for: .read, fileDescriptor: fileDescriptor) {
            try $0.receiveMessage(length, fromAddressOf: addressType)
        }
    }
    
    // MARK: - Private Methods
    
    private func socket(for fileDescriptor: SocketDescriptor) async throws -> SocketState {
        guard let socket = await self.sockets[fileDescriptor] else {
            throw Errno.socketShutdown
        }
        return socket
    }
    
    private func wait<T>(
        for event: FileEvents,
        fileDescriptor: SocketDescriptor,
        _ block: (SocketState) throws -> (T)
    ) async throws -> T {
        // try to poll immediately and not wait
        let pendingEvent: Bool = try await self.storage.update { (state: inout AsyncSocketManager.ManagerState) throws -> (Bool) in
            try state.poll()
            return try state.events(for: fileDescriptor).contains(event) == false
        }
        // try to execute immediately
        guard pendingEvent else {
            let socket = try await socket(for: fileDescriptor)
            return try block(socket)
        }
        // store continuation to resume when event is polled
        try await withThrowingContinuation(for: fileDescriptor) { (continuation: SocketContinuation<(), Swift.Error>) -> () in
            // store pending continuation
            Task {
                await self.storage.update { state in
                    guard state.sockets[fileDescriptor] != nil else {
                        continuation.resume(throwing: Errno.socketShutdown)
                        return
                    }
                    state.sockets[fileDescriptor]?.queue(event: event, continuation)
                }
            }
        }
        // execute after waiting
        let socket = try await socket(for: fileDescriptor)
        return try block(socket)
    }
}

private extension AsyncSocketManager {
    
    var sockets: [SocketDescriptor: SocketState] {
        get async { await storage.state.sockets }
    }
    
    var pollDescriptors: [SocketDescriptor.Poll] {
        get async { await storage.state.pollDescriptors }
    }
    
    var isMonitoring: Bool {
        get async { await storage.state.isMonitoring }
    }
}

extension AsyncSocketManager.ManagerState {
    
    mutating func remove(_ fileDescriptor: SocketDescriptor, error: Error? = nil) {
        guard sockets[fileDescriptor] != nil else {
            return // could have been removed by `poll()`
        }
        log("Remove socket \(fileDescriptor) \(error?.localizedDescription ?? "")")
        // close underlying socket
        try? fileDescriptor.close()
        // cancel all pending actions
        sockets[fileDescriptor]?.dequeueAll(error ?? Errno.connectionAbort)
        // notify
        sockets[fileDescriptor]?.event.yield(.close(error))
        sockets[fileDescriptor]?.event.finish()
        // update sockets to monitor
        sockets[fileDescriptor] = nil
    }
    
    func events(for fileDescriptor: SocketDescriptor) throws -> FileEvents {
        guard let poll = pollDescriptors.first(where: { $0.socket == fileDescriptor }) else {
            throw Errno.socketShutdown
        }
        return poll.returnedEvents
    }
    
    /// Has events.
    @discardableResult
    mutating func poll() throws -> Bool {
        // build poll descriptor array
        let sockets = self.sockets
            .lazy
            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
        pollDescriptors.removeAll(keepingCapacity: true)
        pollDescriptors.reserveCapacity(sockets.count)
        for (fileDescriptor, state) in sockets {
            let poll = SocketDescriptor.Poll(socket: fileDescriptor, events: state.requestedEvents)
            pollDescriptors.append(poll)
        }
        assert(pollDescriptors.count == sockets.count)
        // poll sockets
        do {
            try pollDescriptors.poll()
        }
        catch {
            log("Unable to poll for events. \(error.localizedDescription)")
            throw error
        }
        // wait for concurrent handling
        let hasEvents = pollDescriptors.contains(where: { $0.returnedEvents.isEmpty == false })
        if hasEvents {
            for poll in pollDescriptors {
                if poll.returnedEvents.contains(.write) {
                    canWrite(poll.socket)
                }
                if poll.returnedEvents.contains(.read) {
                    shouldRead(poll.socket)
                }
                if poll.returnedEvents.contains(.invalidRequest) {
                    error(.badFileDescriptor, for: poll.socket)
                }
                if poll.returnedEvents.contains(.hangup) {
                    error(.connectionReset, for: poll.socket)
                }
                if poll.returnedEvents.contains(.error) {
                    error(.connectionAbort, for: poll.socket)
                }
            }
        }
        return hasEvents
    }
    
    mutating func error(_ error: Errno, for fileDescriptor: SocketDescriptor) {
        remove(fileDescriptor, error: error)
    }
    
    mutating func shouldRead(_ fileDescriptor: SocketDescriptor) {
        guard self.sockets[fileDescriptor] != nil else {
            log("Pending read for unknown socket \(fileDescriptor).")
            assertionFailure("\(#function) Unknown socket \(fileDescriptor)")
            return
        }
        // stop waiting
        self.sockets[fileDescriptor]?
            .dequeue(event: .read)?
            .resume()
        // notify
        self.sockets[fileDescriptor]?
            .event
            .yield(.pendingRead)
    }
    
    mutating func canWrite(_ fileDescriptor: SocketDescriptor) {
        guard self.sockets[fileDescriptor] != nil else {
            log("Can write for unknown socket \(fileDescriptor).")
            assertionFailure("\(#function) Unknown socket \(fileDescriptor)")
            return
        }
        // stop waiting
        self.sockets[fileDescriptor]?
            .dequeue(event: .write)?
            .resume()
    }
}

// MARK: - Supporting Types

extension AsyncSocketManager {
    
    actor Storage {
        
        var state = ManagerState()
        
        func update<T>(_ block: (inout ManagerState) throws -> (T)) rethrows -> T {
            try block(&self.state)
        }
    }
    
    final class LockStorage {
        
        private var state = ManagerState()
        
        private let lock = NSLock()
        
        func update(_ block: (inout ManagerState) -> ()) {
            lock.lock()
            defer { lock.unlock() }
            block(&self.state)
        }
    }
    
    struct ManagerState {
        
        var sockets = [SocketDescriptor: SocketState]()
        
        var pollDescriptors = [SocketDescriptor.Poll]()
        
        var isMonitoring = false
    }
}

extension AsyncSocketManager {
    
    struct SocketState {
        
        let fileDescriptor: SocketDescriptor
        
        let event: Socket.Event.Stream.Continuation
        
        private var pendingEvent = [FileEvents: [SocketContinuation<(), Error>]]()
        
        init(fileDescriptor: SocketDescriptor,
             event: Socket.Event.Stream.Continuation
        ) {
            self.fileDescriptor = fileDescriptor
            self.event = event
        }
        
        mutating func dequeueAll(_ error: Error) {
            // cancel all continuations
            for event in pendingEvent.keys {
                while let continuation = dequeue(event: event) {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        mutating func queue(event: FileEvents, _ continuation: SocketContinuation<(), Error>) {
            pendingEvent[event, default: []].append(continuation)
        }
        
        mutating func dequeue(event: FileEvents) -> SocketContinuation<(), Error>? {
            guard pendingEvent[event, default: []].isEmpty == false else {
                return nil
            }
            return pendingEvent[event, default: []].removeFirst()
        }
        
        var requestedEvents: FileEvents {
            var events: FileEvents = [
                .read,
                .error,
                .hangup,
                .invalidRequest
            ]
            if pendingEvent[.write, default: []].isEmpty == false {
                events.insert(.write)
            }
            return events
        }
    }
}

extension AsyncSocketManager.SocketState {
    
    func write(_ data: Data) throws -> Int {
        log("Will write \(data.count) bytes to \(fileDescriptor)")
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.write($0)
        }
        // notify
        event.yield(.write(byteCount))
        return byteCount
    }
    
    func sendMessage(_ data: Data) throws -> Int {
        log("Will send message with \(data.count) bytes to \(fileDescriptor)")
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0)
        }
        // notify
        event.yield(.write(byteCount))
        return byteCount
    }
    
    func sendMessage<Address: SocketAddress>(_ data: Data, to address: Address) throws -> Int {
        log("Will send message with \(data.count) bytes to \(fileDescriptor)")
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0, to: address)
        }
        // notify
        event.yield(.write(byteCount))
        return byteCount
    }
    
    func read(_ length: Int) throws -> Data {
        log("Will read \(length) bytes from \(fileDescriptor)")
        var data = Data(count: length)
        let bytesRead = try data.withUnsafeMutableBytes {
            try fileDescriptor.read(into: $0)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        // notify
        event.yield(.read(bytesRead))
        return data
    }
    
    func receiveMessage(_ length: Int) throws -> Data {
        log("Will receive message with \(length) bytes from \(fileDescriptor)")
        var data = Data(count: length)
        let bytesRead = try data.withUnsafeMutableBytes {
            try fileDescriptor.receive(into: $0)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        // notify
        event.yield(.read(bytesRead))
        return data
    }
    
    func receiveMessage<Address: SocketAddress>(_ length: Int, fromAddressOf addressType: Address.Type = Address.self) throws -> (Data, Address) {
        log("Will receive message with \(length) bytes from \(fileDescriptor)")
        var data = Data(count: length)
        let (bytesRead, address) = try data.withUnsafeMutableBytes {
            try fileDescriptor.receive(into: $0, fromAddressOf: addressType)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        // notify
        event.yield(.read(bytesRead))
        return (data, address)
    }
}

// Socket logging
fileprivate func log(_ message: String) {
    if let logger = AsyncSocketManager.shared.configuration.log {
        logger(message)
    } else {
        #if DEBUG
        if debugLogEnabled {
            NSLog("Socket: " + message)
        }
        #endif
    }
}

#if DEBUG
let debugLogEnabled = ProcessInfo.processInfo.environment["SWIFTSOCKETDEBUG"] == "1"
#endif
