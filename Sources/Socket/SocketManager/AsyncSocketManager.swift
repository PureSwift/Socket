//
//  AsyncSocketManager.swift
//
//
//  Created by Alsey Coleman Miller on 4/12/23.
//

import Foundation

public struct AsyncSocketConfiguration: Sendable {
    
    /// Log
    public var log: (@Sendable (String) -> ())?
    
    /// Task priority for backgroud socket polling.
    public var monitorPriority: TaskPriority
    
    /// Interval in nanoseconds for monitoring / polling socket.
    public var monitorInterval: UInt64
    
    public init(
        log: (@Sendable (String) -> ())? = nil,
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

#if os(Linux) || os(Android)
internal typealias PlatformEventQueue = EpollEventQueue
#elseif canImport(Darwin)
internal typealias PlatformEventQueue = KqueueEventQueue
#else
internal typealias PlatformEventQueue = PollEventQueue
#endif

/// Async Socket Manager
internal actor AsyncSocketManager: SocketManager {

    // MARK: - Properties

    fileprivate var state = ManagerState()

    fileprivate var eventQueue: PlatformEventQueue?
    
    /// Events every socket is registered for.
    ///
    /// Write readiness is not included. A connected socket is almost always writable, so a
    /// standing registration would make every wait return immediately for every idle socket.
    /// It is added on demand while a write is pending, see ``addInterest(_:for:)``.
    internal static let monitoredEvents: FileEvents = [
        .read,
        .readUrgent,
        .error,
        .hangup,
        .invalidRequest
    ]

    // MARK: - Initialization

    static let shared = AsyncSocketManager()
    
    private init() { }
    
    // MARK: - Methods
    
    func add(
        _ fileDescriptor: SocketDescriptor
    ) -> Socket.Event.Stream {
        // The kernel only hands back a descriptor number once the previous owner is gone,
        // so any existing entry belongs to a socket that was closed without notifying us.
        // Kernel event queues drop closed descriptors silently, unlike `poll(2)` reporting `POLLNVAL`.
        if state.sockets.keys.contains(fileDescriptor) {
            log("Discard stale socket \(fileDescriptor)")
            discard(fileDescriptor)
        }
        state.detached.remove(fileDescriptor)
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
        // register with kernel event queue
        do {
            if eventQueue == nil {
                eventQueue = try PlatformEventQueue(maxEvents: 1024)
            }
            try eventQueue?.add(fileDescriptor, events: Self.monitoredEvents)
            state.interests[fileDescriptor] = Self.monitoredEvents
        }
        catch {
            log("Unable to register socket for events. \(error)")
            assertionFailure("Unable to register socket for events. \(error)")
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
        if state.sockets[fileDescriptor] != nil {
            log("Remove socket \(fileDescriptor)")
            // deregister before closing, a closed descriptor cannot be deregistered by number
            discard(fileDescriptor)
        } else if state.detached.remove(fileDescriptor) == nil {
            return // already closed by its owner
        }
        // close on behalf of the owner, including sockets left open by a hangup
        try? fileDescriptor.close()
    }

    /// Deregister a file descriptor and tear down its state without closing it.
    ///
    /// The manager never closes a descriptor it did not open. Closing one that the owner
    /// still holds lets the kernel hand the same number to a new socket, and a later
    /// ``remove(_:)`` would then close that unrelated socket instead. A descriptor kept
    /// open this way is recorded in `detached` so its owner can still close it once.
    private func discard(_ fileDescriptor: SocketDescriptor, detach: Bool = false) {
        guard let socket = state.sockets[fileDescriptor] else {
            return
        }
        if detach {
            state.detached.insert(fileDescriptor)
        }
        try? eventQueue?.remove(fileDescriptor)
        state.interests[fileDescriptor] = nil
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
    ) async throws -> (Data, Address) where Address: Sendable {
        let socket = try await wait(for: .read, fileDescriptor: fileDescriptor)
        await log("Will receive message with \(length) bytes from \(fileDescriptor)")
        return try await socket.receiveMessage(length, fromAddressOf: addressType)
    }
    
    nonisolated func listen(backlog: Int, for fileDescriptor: SocketDescriptor) async throws {
        let socket = try await self.socket(for: fileDescriptor)
        try await socket.listen(backlog: backlog)
    }
    
    /// Accept a connection on a socket.
    nonisolated func accept(for fileDescriptor: SocketDescriptor) async throws -> SocketDescriptor {
        let socket = try await wait(for: .read, fileDescriptor: fileDescriptor)
        return try await socket.accept()
    }
    
    /// Accept a connection on a socket.
    nonisolated func accept<Address: SocketAddress>(
        _ address: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (fileDescriptor: SocketDescriptor, address: Address) where Address: Sendable {
        let socket = try await wait(for: .read, fileDescriptor: fileDescriptor)
        return try await socket.accept(address)
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
        // MEMO: Using [weak self] instead of [unowned self] to work around a compiler bug.
        // This issue only occurs in CI environments, where using [unowned self] causes a compiler crash under certain conditions.
        Task.detached(priority: state.configuration.monitorPriority) { [weak self] in
            await self?.run()
        }
    }
    
    func run() async {
        var tasks = [Task<Void, Never>]()
        while self.state.isMonitoring {
            do {
                tasks.reserveCapacity(state.sockets.count)
                // poll
                let hasEvents = try poll(&tasks)
                // stop monitoring if no sockets
                if state.sockets.isEmpty {
                    state.isMonitoring = false
                }
                // wait for each task to complete
                for task in tasks {
                    await task.value
                }
                tasks.removeAll(keepingCapacity: true)
                // sleep
                let sleepInterval = state.configuration.monitorInterval * (hasEvents ? 1 : 2)
                try await Task.sleep(nanoseconds: sleepInterval)
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

    /// Subscribe to additional events for a registered socket.
    func addInterest(_ events: FileEvents, for fileDescriptor: SocketDescriptor) {
        guard let current = state.interests[fileDescriptor] else { return }
        setInterest(current.union(events), for: fileDescriptor)
    }

    /// Stop monitoring events that no longer have a pending operation.
    func removeInterest(_ events: FileEvents, for fileDescriptor: SocketDescriptor) {
        guard let current = state.interests[fileDescriptor] else { return }
        setInterest(current.subtracting(events).union(Self.monitoredEvents), for: fileDescriptor)
    }

    private func setInterest(_ events: FileEvents, for fileDescriptor: SocketDescriptor) {
        // skip the syscall when the mask is unchanged
        guard state.interests[fileDescriptor] != events else { return }
        state.interests[fileDescriptor] = events
        do { try eventQueue?.update(fileDescriptor, events: events) }
        catch { log("Unable to update events for \(fileDescriptor). \(error)") }
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
        // subscribe to events that are not monitored by default, like write readiness
        await addInterest(events, for: fileDescriptor)
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
        guard state.sockets.isEmpty == false else { return false }
        var hasEvents = false
        do {
            try eventQueue?.wait(timeout: 0) { buffer in
                hasEvents = buffer.isEmpty == false
                for readiness in buffer {
                    guard let socket = state.sockets[readiness.fileDescriptor] else {
                        continue // stale event for a removed descriptor
                    }
                    tasks.append(process(readiness, socket: socket))
                }
            }
        }
        catch {
            log("Unable to poll for events. \(error.localizedDescription)")
            throw error
        }
        return hasEvents
    }

    func process(_ readiness: SocketReadiness, socket: AsyncSocketManager.SocketState) -> Task<Void, Never> {
        Task(priority: state.configuration.monitorPriority) {
            if readiness.events.contains(.read) {
                await socket.event(.read, notification: socket.isListening ? .connection : .read)
            }
            if readiness.events.contains(.write) {
                await socket.event(.write, notification: .write)
                // unsubscribe once nothing is waiting to write, the socket stays
                // writable and would otherwise report readiness on every wait
                if await socket.isWaiting(for: .write) == false {
                    removeInterest(.write, for: readiness.fileDescriptor)
                }
            }
            if readiness.events.contains(.invalidRequest) {
                error(.badFileDescriptor, for: readiness.fileDescriptor)
            }
            if readiness.events.contains(.error) {
                error(.connectionReset, for: readiness.fileDescriptor)
            }
            if readiness.events.contains(.hangup) {
                hangup(readiness.fileDescriptor)
            }
        }
    }
    
    func error(_ error: Errno, for fileDescriptor: SocketDescriptor) {
        state.sockets[fileDescriptor]?.continuation.yield(.error(error))
        // stop monitoring but leave the descriptor open, see `discard(_:detach:)`
        discard(fileDescriptor, detach: true)
    }

    func hangup(_ fileDescriptor: SocketDescriptor) {
        discard(fileDescriptor, detach: true)
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
    
    func listen(backlog: Int) throws {
        try fileDescriptor.listen(backlog: backlog)
        isListening = true
    }
    
    func accept() throws -> SocketDescriptor {
        try fileDescriptor.accept()
    }
    
    func accept<Address: SocketAddress>(_ address: Address.Type) throws -> (SocketDescriptor, Address) {
        try fileDescriptor.accept(address)
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
    
    func isWaiting(for event: FileEvents) -> Bool {
        eventContinuation[event, default: []].isEmpty == false
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
    
    struct ManagerState: Sendable {
        
        var configuration = AsyncSocketConfiguration()
        
        var sockets = [SocketDescriptor: SocketState]()

        /// Events each socket is currently registered for.
        var interests = [SocketDescriptor: FileEvents]()

        /// Sockets no longer monitored whose descriptor is still open.
        var detached = Set<SocketDescriptor>()

        var isMonitoring = false
    }
    
    actor SocketState: Sendable {
        
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
