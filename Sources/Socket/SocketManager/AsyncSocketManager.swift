//
//  AsyncSocketManager.swift
//
//
//  Created by Alsey Coleman Miller on 4/12/23.
//

import Foundation

public struct AsyncSocketConfiguration {
    
    /// Log
    public var log: ((String) -> ())?
    
    /// Task priority for backgroud socket polling.
    public var monitorPriority: TaskPriority
    
    /// Interval in nanoseconds for monitoring / polling socket.
    public var monitorInterval: UInt64
    
    public init(
        log: ((String) -> ())? = nil,
        monitorPriority: TaskPriority = .userInitiated,
        monitorInterval: UInt64 = 100_000_000
    ) {
        self.log = log
        self.monitorPriority = monitorPriority
        self.monitorInterval = monitorInterval
    }
}

extension AsyncSocketConfiguration: SocketManagerConfiguration {
    
    public static nonisolated var manager: some SocketManager {
        AsyncSocketManager.shared
    }
    
    public func configureManager() {
        Task {
            await AsyncSocketManager.shared.updateConfiguration(self)
        }
    }
}

/// Async Socket Manager
internal actor AsyncSocketManager: SocketManager {
    
    // MARK: - Properties
    
    fileprivate var state = ManagerState()
    
    // MARK: - Initialization
    
    static let shared = AsyncSocketManager()
    
    private init() { }
    
    // MARK: - Methods
    
    func add(
        _ fileDescriptor: SocketDescriptor
    ) -> Socket.Event.Stream {
        guard state.sockets.keys.contains(fileDescriptor) == false else {
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
        let eventStream = Socket.Event.Stream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            state.sockets[fileDescriptor] = SocketState(
                fileDescriptor: fileDescriptor,
                manager: self,
                continuation: continuation
            )
        }
        // start monitoring
        startMonitoring()
        return eventStream
    }
    
    func remove(_ fileDescriptor: SocketDescriptor) {
        guard let socket = state.sockets[fileDescriptor] else {
            return // could have been removed previously
        }
        log("Remove socket \(fileDescriptor)")
        // close underlying socket
        try? fileDescriptor.close()
        // cancel all pending actions
        Task(priority: .userInitiated) {
            await socket.dequeueAll(Errno.connectionAbort)
        }
        // notify
        socket.continuation.yield(.close)
        socket.continuation.finish()
        // update sockets to monitor
        state.sockets[fileDescriptor] = nil
    }
    
    /// Write data to managed file descriptor.
    nonisolated func write(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        let socket = try await wait(for: .write, fileDescriptor: fileDescriptor)
        await log("Will write \(data.count) bytes to \(fileDescriptor)")
        return try await socket.write(data)
    }
    
    /// Read managed file descriptor.
    nonisolated func read(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        let socket = try await wait(for: .read, fileDescriptor: fileDescriptor)
        await log("Will read \(length) bytes from \(fileDescriptor)")
        return try await socket.read(length)
    }
    
    nonisolated func sendMessage(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        let socket = try await wait(for: .write, fileDescriptor: fileDescriptor)
        await log("Will send message with \(data.count) bytes to \(fileDescriptor)")
        return try await socket.sendMessage(data)
    }
    
    nonisolated func sendMessage<Address: SocketAddress>(
        _ data: Data,
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        let socket = try await wait(for: .write, fileDescriptor: fileDescriptor)
        await log("Will send message with \(data.count) bytes to \(fileDescriptor)")
        return try await socket.sendMessage(data, to: address)
    }
    
    nonisolated func receiveMessage(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        let socket = try await wait(for: .read, fileDescriptor: fileDescriptor)
        await log("Will receive message with \(length) bytes from \(fileDescriptor)")
        return try await socket.receiveMessage(length)
    }
    
    nonisolated func receiveMessage<Address: SocketAddress>(
        _ length: Int,
        fromAddressOf addressType: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (Data, Address) {
        let socket = try await wait(for: .read, fileDescriptor: fileDescriptor)
        await log("Will receive message with \(length) bytes from \(fileDescriptor)")
        return try await socket.receiveMessage(length, fromAddressOf: addressType)
    }
    
    /// Accept a connection on a socket.
    nonisolated func accept(for fileDescriptor: SocketDescriptor) async throws -> SocketDescriptor {
        let socket = try await socket(for: fileDescriptor)
        let result = try await retry(sleep: state.configuration.monitorInterval) {
            fileDescriptor._accept(retryOnInterrupt: true)
        }.get()
        socket.continuation.yield(.connection)
        return result
    }
    
    /// Accept a connection on a socket.
    nonisolated func accept<Address: SocketAddress>(
        _ address: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (fileDescriptor: SocketDescriptor, address: Address) {
        let socket = try await socket(for: fileDescriptor)
        let result = try await retry(sleep: state.configuration.monitorInterval) {
            fileDescriptor._accept(address, retryOnInterrupt: true)
        }.get()
        socket.continuation.yield(.connection)
        return result
    }
    
    /// Initiate a connection on a socket.
    nonisolated func connect<Address: SocketAddress>(
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws {
        let socket = try await socket(for: fileDescriptor)
        try await retry(sleep: state.configuration.monitorInterval) {
            fileDescriptor._connect(to: address, retryOnInterrupt: true)
        }.get()
        socket.continuation.yield(.connection)
    }
}

// MARK: - Private Methods

private extension AsyncSocketManager {
    
    func updateConfiguration(_ configuration: AsyncSocketConfiguration) {
        self.state.configuration = configuration
    }
    
    func startMonitoring() {
        guard state.isMonitoring == false
            else { return }
        log("Will start monitoring")
        state.isMonitoring = true
        // Create top level task to monitor
        Task.detached(priority: state.configuration.monitorPriority) { [unowned self] in
            await self.run()
        }
    }
    
    func run() async {
        var tasks = [Task<Void, Never>]()
        while self.state.isMonitoring {
            do {
                tasks.reserveCapacity(state.sockets.count * 2)
                // poll
                let hasEvents = try poll(&tasks)
                // stop monitoring if no sockets
                if state.pollDescriptors.isEmpty {
                    state.isMonitoring = false
                }
                // wait for each task to complete
                for task in tasks {
                    await task.value
                }
                tasks.removeAll(keepingCapacity: true)
                // sleep
                if hasEvents == false {
                    try await Task.sleep(nanoseconds: state.configuration.monitorInterval)
                }
            }
            catch {
                log("Socket monitoring failed. \(error.localizedDescription)")
                assertionFailure("Socket monitoring failed. \(error.localizedDescription)")
                state.isMonitoring = false
                return
            }
        }
    }
    
    func contains(_ fileDescriptor: SocketDescriptor) -> Bool {
        return state.sockets.keys.contains(fileDescriptor)
    }
    
    nonisolated func wait(
        for events: FileEvents,
        fileDescriptor: SocketDescriptor
    ) async throws -> SocketState {
        // wait
        let socket = try await socket(for: fileDescriptor)
        guard await socket.pendingEvents.contains(events) == false else {
            return socket // execute immediately
        }
        // store continuation to resume when event is polled
        try await withThrowingContinuation(for: fileDescriptor) { (continuation: SocketContinuation<(), Swift.Error>) -> () in
            // store pending continuation
            Task(priority: .userInitiated) {
                await log("Will wait for \(events) for \(fileDescriptor)")
                await socket.queue(events, continuation)
            }
        }
        return socket
    }
    
    func socket(
        for fileDescriptor: SocketDescriptor
    ) throws -> AsyncSocketManager.SocketState {
        guard let socket = state.sockets[fileDescriptor] else {
            throw Errno.socketShutdown
        }
        return socket
    }
    
    /// Poll for events.
    @discardableResult
    func poll(_ tasks: inout [Task<Void, Never>]) throws -> Bool {
        // build poll descriptor array
        let sockets = state.sockets
            .lazy
            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
        state.pollDescriptors.removeAll(keepingCapacity: true)
        state.pollDescriptors.reserveCapacity(sockets.count)
        let events: FileEvents = [
            .read,
            .readUrgent,
            .write,
            .error,
            .hangup,
            .invalidRequest
        ]
        for (fileDescriptor, _) in sockets {
            let poll = SocketDescriptor.Poll(
                socket: fileDescriptor,
                events: events
            )
            state.pollDescriptors.append(poll)
        }
        assert(state.pollDescriptors.count == sockets.count)
        // poll sockets
        do {
            try state.pollDescriptors.poll()
        }
        catch {
            log("Unable to poll for events. \(error.localizedDescription)")
            throw error
        }
        // wait for concurrent handling
        let hasEvents = state.pollDescriptors.contains(where: { $0.returnedEvents.isEmpty == false })
        if hasEvents {
            for poll in state.pollDescriptors {
                guard let state = state.sockets[poll.socket] else {
                    preconditionFailure()
                    continue
                }
                process(poll, socket: state, tasks: &tasks)
            }
        }
        return hasEvents
    }
    
    func process(_ poll: SocketDescriptor.Poll, socket: AsyncSocketManager.SocketState, tasks: inout [Task<Void, Never>]) {
        /*
        let isListening = self.sockets[poll.socket]?.isListening ?? false
        if isListening, poll.returnedEvents.contains([.read, .write]) {
            event([.read, .write], notification: .connection, for: poll.socket)
        } else {
            if poll.returnedEvents.contains(.read) {
                event(.read, notification: .read, for: poll.socket)
            }
            if poll.returnedEvents.contains(.write) {
                event(.write, notification: .write, for: poll.socket)
            }
        }*/
        if poll.returnedEvents.contains(.read) {
            let task = Task {
                await socket.event(.read, notification: .read)
            }
            tasks.append(task)
        }
        if poll.returnedEvents.contains(.write) {
            let task = Task {
                await socket.event(.write, notification: .write)
            }
            tasks.append(task)
        }
        if poll.returnedEvents.contains(.invalidRequest) {
            error(.badFileDescriptor, for: poll.socket)
        }
        if poll.returnedEvents.contains(.error) {
            error(.connectionReset, for: poll.socket)
        }
        if poll.returnedEvents.contains(.hangup) {
            hangup(poll.socket)
        }
    }
    
    func error(_ error: Errno, for fileDescriptor: SocketDescriptor) {
        state.sockets[fileDescriptor]?.continuation.yield(.error(error))
        remove(fileDescriptor)
    }
    
    func hangup(_ fileDescriptor: SocketDescriptor) {
        remove(fileDescriptor)
    }
}
 
extension AsyncSocketManager.SocketState {
    
    func write(_ data: Data) throws -> Int {
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.write($0)
        }
        // notify
        didWrite(byteCount)
        return byteCount
    }
    
    func sendMessage(_ data: Data) throws -> Int {
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0)
        }
        // notify
        didWrite(byteCount)
        return byteCount
    }
    
    func sendMessage<Address: SocketAddress>(_ data: Data, to address: Address) throws -> Int {
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0, to: address)
        }
        // notify
        didWrite(byteCount)
        return byteCount
    }
    
    func read(_ length: Int) throws -> Data {
        var data = Data(count: length)
        let bytesRead = try data.withUnsafeMutableBytes {
            try fileDescriptor.read(into: $0)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        // notify
        didRead(bytesRead)
        return data
    }
    
    func receiveMessage(_ length: Int) throws -> Data {
        var data = Data(count: length)
        let bytesRead = try data.withUnsafeMutableBytes {
            try fileDescriptor.receive(into: $0)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        // notify
        didRead(bytesRead)
        return data
    }
    
    func receiveMessage<Address: SocketAddress>(_ length: Int, fromAddressOf addressType: Address.Type) throws -> (Data, Address) {
        var data = Data(count: length)
        let (bytesRead, address) = try data.withUnsafeMutableBytes {
            try fileDescriptor.receive(into: $0, fromAddressOf: addressType)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        // notify
        didRead(bytesRead)
        return (data, address)
    }
}

fileprivate extension AsyncSocketManager.SocketState {
    
    func didRead(_ bytes: Int) {
        pendingEvents.remove(.read)
        continuation.yield(.didRead(bytes))
    }
    
    func didWrite(_ bytes: Int) {
        pendingEvents.remove(.write)
        continuation.yield(.didWrite(bytes))
    }
    
    func dequeueAll(_ error: Error) {
        // cancel all continuations
        for event in eventContinuation.keys {
            while let continuation = dequeue(event) {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func queue(_ event: FileEvents, _ continuation: SocketContinuation<(), Error>) {
        guard pendingEvents.contains(event) == false else {
            continuation.resume()
            return
        }
        eventContinuation[event, default: []].append(continuation)
    }
    
    func dequeue(_ event: FileEvents) -> SocketContinuation<(), Error>? {
        guard eventContinuation[event, default: []].isEmpty == false else {
            return nil
        }
        return eventContinuation[event, default: []].removeFirst()
    }
    
    func event(
        _ event: FileEvents,
        notification: Socket.Event
    ) {
        dequeue(event)?.resume()
        guard pendingEvents.contains(event) == false else {
            return
        }
        pendingEvents.insert(event)
        continuation.yield(notification)
    }
}

extension AsyncSocketManager {
    
    #if DEBUG
    static let debugLogEnabled = ProcessInfo.processInfo.environment["SWIFTSOCKETDEBUG"] == "1"
    #endif
    
    func log(_ message: String) {
        if let logger = state.configuration.log {
            logger(message)
        } else {
            #if DEBUG
            if Self.debugLogEnabled {
                NSLog("Socket: " + message)
            }
            #endif
        }
    }
}

// MARK: - Supporting Types

extension AsyncSocketManager {
    
    struct ManagerState {
        
        var configuration = AsyncSocketConfiguration()
        
        var sockets = [SocketDescriptor: SocketState]()
        
        var pollDescriptors = [SocketDescriptor.Poll]()
        
        var isMonitoring = false
    }
    
    actor SocketState {
        
        let fileDescriptor: SocketDescriptor

        unowned let manager: AsyncSocketManager
        
        let continuation: Socket.Event.Stream.Continuation
        
        var pendingEvents: FileEvents = []
        
        var eventContinuation = [FileEvents: [SocketContinuation<(), Error>]]()
        
        var isListening = false
        
        init(
            fileDescriptor: SocketDescriptor,
            manager: AsyncSocketManager,
            continuation: Socket.Event.Stream.Continuation
        ) {
            self.fileDescriptor = fileDescriptor
            self.manager = manager
            self.continuation = continuation
        }
    }
}
