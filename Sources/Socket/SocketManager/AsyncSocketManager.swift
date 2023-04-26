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
        monitorPriority: TaskPriority = .medium,
        monitorInterval: UInt64 = 100_000_000
    ) {
        self.log = log
        self.monitorPriority = monitorPriority
        self.monitorInterval = monitorInterval
    }
}

extension AsyncSocketConfiguration: SocketManagerConfiguration {
    
    public static var manager: some SocketManager {
        AsyncSocketManager.shared
    }
    
    public func configureManager() {
        Task {
            await AsyncSocketManager.shared.storage.update {
                $0.configuration = self
            }
        }
    }
}

/// Async Socket Manager
internal final class AsyncSocketManager: SocketManager {
    
    // MARK: - Properties
    
    fileprivate let storage = Storage()
    
    // MARK: - Initialization
    
    static let shared = AsyncSocketManager()
    
    private init() { }
    
    // MARK: - Methods
    
    func add(
        _ fileDescriptor: SocketDescriptor
    ) async -> Socket.Event.Stream {
        guard await sockets.keys.contains(fileDescriptor) == false else {
            fatalError("Another socket for file descriptor \(fileDescriptor) already exists.")
        }
        await log("Add socket \(fileDescriptor)")
        // make sure its non blocking
        do {
            var status = try fileDescriptor.getStatus()
            if status.contains(.nonBlocking) == false {
                status.insert(.nonBlocking)
                try fileDescriptor.setStatus(status)
            }
        }
        catch {
            await log("Unable to set non blocking. \(error)")
            assertionFailure("Unable to set non blocking. \(error)")
        }
        // append socket with events continuation
        let eventStream = await storage.update { manager in
            Socket.Event.Stream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                manager.sockets[fileDescriptor] = SocketState(
                    fileDescriptor: fileDescriptor,
                    continuation: continuation
                )
            }
        }
        // start monitoring
        await startMonitoring()
        return eventStream
    }
    
    func remove(_ fileDescriptor: SocketDescriptor) async {
        await storage.update {
            $0.remove(fileDescriptor)
        }
    }
    
    /// Write data to managed file descriptor.
    func write(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        try await wait(for: .write, fileDescriptor: fileDescriptor)
        return try await storage.update {
            $0.log("Will write \(data.count) bytes to \(fileDescriptor)")
            return try $0.socket(for: fileDescriptor) {
                try $0.write(data)
            }
        }
    }
    
    /// Read managed file descriptor.
    func read(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        try await wait(for: .read, fileDescriptor: fileDescriptor)
        return try await storage.update {
            $0.log("Will read \(length) bytes from \(fileDescriptor)")
            return try $0.socket(for: fileDescriptor) {
                try $0.read(length)
            }
        }
    }
    
    func sendMessage(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        try await wait(for: .write, fileDescriptor: fileDescriptor)
        return try await storage.update {
            $0.log("Will send message with \(data.count) bytes to \(fileDescriptor)")
            return try $0.socket(for: fileDescriptor) {
                try $0.sendMessage(data)
            }
        }
    }
    
    func sendMessage<Address: SocketAddress>(
        _ data: Data,
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        try await wait(for: .write, fileDescriptor: fileDescriptor)
        return try await storage.update {
            $0.log("Will send message with \(data.count) bytes to \(fileDescriptor)")
            return try $0.socket(for: fileDescriptor) {
                try $0.sendMessage(data, to: address)
            }
        }
    }
    
    func receiveMessage(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        try await wait(for: .read, fileDescriptor: fileDescriptor)
        return try await storage.update {
            $0.log("Will receive message with \(length) bytes from \(fileDescriptor)")
            return try $0.socket(for: fileDescriptor) {
                try $0.receiveMessage(length)
            }
        }
    }
    
    func receiveMessage<Address: SocketAddress>(
        _ length: Int,
        fromAddressOf addressType: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (Data, Address) {
        try await wait(for: .read, fileDescriptor: fileDescriptor)
        return try await storage.update {
            $0.log("Will receive message with \(length) bytes from \(fileDescriptor)")
            return try $0.socket(for: fileDescriptor) {
                try $0.receiveMessage(length, fromAddressOf: addressType)
            }
        }
    }
    
    /// Accept a connection on a socket.
    func accept(for fileDescriptor: SocketDescriptor) async throws -> SocketDescriptor {
        //try await wait(for: [.read, .write], fileDescriptor: fileDescriptor)
        //return try fileDescriptor.accept()
        try await retry(sleep: configuration.monitorInterval) {
            fileDescriptor._accept(retryOnInterrupt: true)
        }.get()
    }
    
    /// Accept a connection on a socket.
    func accept<Address: SocketAddress>(
        _ address: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (fileDescriptor: SocketDescriptor, address: Address) {
        //try await wait(for: [.read, .write], fileDescriptor: fileDescriptor)
        //return try fileDescriptor.accept(address)
        try await retry(sleep: configuration.monitorInterval) {
            fileDescriptor._accept(address, retryOnInterrupt: true)
        }.get()
    }
    
    /// Initiate a connection on a socket.
    func connect<Address: SocketAddress>(
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws {
        //try await wait(for: [.write], fileDescriptor: fileDescriptor)
        //try fileDescriptor.connect(to: address)
        try await retry(sleep: configuration.monitorInterval) {
            fileDescriptor._connect(to: address, retryOnInterrupt: true)
        }.get()
    }
    
    // MARK: - Private Methods
    
    private func startMonitoring() async {
        guard await storage.update({
            guard $0.isMonitoring == false else { return false }
            $0.log("Will start monitoring")
            $0.isMonitoring = true
            return true
        }) else { return }
        // Create top level task to monitor
        let configuration = await AsyncSocketManager.shared.configuration
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
                    //log("Socket monitoring failed. \(error.localizedDescription)")
                    assertionFailure("Socket monitoring failed. \(error.localizedDescription)")
                    await storage.update {
                        $0.isMonitoring = false
                    }
                }
            }
        }
    }
    
    private func contains(_ fileDescriptor: SocketDescriptor) async -> Bool {
        return await sockets.keys.contains(fileDescriptor)
    }
    
    private func wait(
        for events: FileEvents,
        fileDescriptor: SocketDescriptor
    ) async throws {
        // wait
        await self.storage.update { state in
            // try to execute immediately
            guard let pendingEvents = state.sockets[fileDescriptor]?.pendingEvents,
                pendingEvents.contains(events) == false else {
                return
            }
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
                    state.sockets[fileDescriptor]?.queue(events, continuation)
                }
            }
        }
    }
}

private extension AsyncSocketManager {
    
    var configuration: AsyncSocketConfiguration {
        get async { await storage.state.configuration }
    }
    
    var sockets: [SocketDescriptor: SocketState] {
        get async { await storage.state.sockets }
    }
    
    var pollDescriptors: [SocketDescriptor.Poll] {
        get async { await storage.state.pollDescriptors }
    }
    
    var isMonitoring: Bool {
        get async { await storage.state.isMonitoring }
    }
    
    func log(_ message: String) async {
        await storage.state.log(message)
    }
}

extension AsyncSocketManager.ManagerState {
    
    mutating func socket<T>(for fileDescriptor: SocketDescriptor, _ block: (inout AsyncSocketManager.SocketState) throws -> T) throws -> T {
        guard var socket = self.sockets[fileDescriptor] else {
            throw Errno.socketShutdown
        }
        let result = try block(&socket)
        self.sockets[fileDescriptor] = socket
        return result
    }
    
    mutating func remove(_ fileDescriptor: SocketDescriptor) {
        guard sockets[fileDescriptor] != nil else {
            return // could have been removed previously
        }
        log("Remove socket \(fileDescriptor)")
        // close underlying socket
        try? fileDescriptor.close()
        // cancel all pending actions
        sockets[fileDescriptor]?.dequeueAll(Errno.connectionAbort)
        // notify
        sockets[fileDescriptor]?.continuation.yield(.close)
        sockets[fileDescriptor]?.continuation.finish()
        // update sockets to monitor
        sockets[fileDescriptor] = nil
    }
    
    /// Poll for events.
    @discardableResult
    mutating func poll() throws -> Bool {
        // build poll descriptor array
        let sockets = self.sockets
            .lazy
            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
        pollDescriptors.removeAll(keepingCapacity: true)
        pollDescriptors.reserveCapacity(sockets.count)
        let events: FileEvents = [
            .read,
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
                process(poll)
            }
        }
        return hasEvents
    }
    
    mutating func process(_ poll: SocketDescriptor.Poll) {
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
    
    mutating func error(_ error: Errno, for fileDescriptor: SocketDescriptor) {
        self.sockets[fileDescriptor]?.continuation.yield(.error(error))
        remove(fileDescriptor)
    }
    
    mutating func hangup(_ fileDescriptor: SocketDescriptor) {
        remove(fileDescriptor)
    }
    
    mutating func event(
        _ event: FileEvents,
        notification: Socket.Event,
        for fileDescriptor: SocketDescriptor
    ) {
        guard var state = self.sockets[fileDescriptor] else {
            assertionFailure()
            return
        }
        guard state.pendingEvents.contains(event) == false else {
            return
        }
        state.pendingEvents.insert(event)
        state.continuation.yield(notification)
        self.sockets[fileDescriptor] = state
    }
}

extension AsyncSocketManager.SocketState {
    
    mutating func write(_ data: Data) throws -> Int {
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.write($0)
        }
        // notify
        didWrite(byteCount)
        return byteCount
    }
    
    mutating func sendMessage(_ data: Data) throws -> Int {
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0)
        }
        // notify
        didWrite(byteCount)
        return byteCount
    }
    
    mutating func sendMessage<Address: SocketAddress>(_ data: Data, to address: Address) throws -> Int {
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0, to: address)
        }
        // notify
        didWrite(byteCount)
        return byteCount
    }
    
    mutating func read(_ length: Int) throws -> Data {
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
    
    mutating func receiveMessage(_ length: Int) throws -> Data {
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
    
    mutating func receiveMessage<Address: SocketAddress>(_ length: Int, fromAddressOf addressType: Address.Type) throws -> (Data, Address) {
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
    
    mutating func didRead(_ bytes: Int) {
        pendingEvents.remove(.read)
        continuation.yield(.didRead(bytes))
    }
    
    mutating func didWrite(_ bytes: Int) {
        pendingEvents.remove(.write)
        continuation.yield(.didWrite(bytes))
    }
    
    mutating func dequeueAll(_ error: Error) {
        // cancel all continuations
        for event in eventContinuation.keys {
            while let continuation = dequeue(event) {
                continuation.resume(throwing: error)
            }
        }
    }
    
    mutating func queue(_ event: FileEvents, _ continuation: SocketContinuation<(), Error>) {
        eventContinuation[event, default: []].append(continuation)
    }
    
    mutating func dequeue(_ event: FileEvents) -> SocketContinuation<(), Error>? {
        guard eventContinuation[event, default: []].isEmpty == false else {
            return nil
        }
        return eventContinuation[event, default: []].removeFirst()
    }
}

extension AsyncSocketManager.ManagerState {
    
    #if DEBUG
    static let debugLogEnabled = ProcessInfo.processInfo.environment["SWIFTSOCKETDEBUG"] == "1"
    #endif
    
    func log(_ message: String) {
        if let logger = configuration.log {
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
    
    actor Storage {
        
        var state = ManagerState()
        
        func update<T>(_ block: (inout ManagerState) throws -> (T)) rethrows -> T {
            try block(&self.state)
        }
    }
    
    struct ManagerState {
        
        var configuration = AsyncSocketConfiguration()
        
        var sockets = [SocketDescriptor: SocketState]()
        
        var pollDescriptors = [SocketDescriptor.Poll]()
        
        var isMonitoring = false
    }
    
    struct SocketState {
        
        let fileDescriptor: SocketDescriptor
        
        let continuation: Socket.Event.Stream.Continuation
        
        var pendingEvents: FileEvents = []
        
        var eventContinuation = [FileEvents: [SocketContinuation<(), Error>]]()
        
        var isListening = false
        
        init(
            fileDescriptor: SocketDescriptor,
            continuation: Socket.Event.Stream.Continuation
        ) {
            self.fileDescriptor = fileDescriptor
            self.continuation = continuation
        }
    }
}
