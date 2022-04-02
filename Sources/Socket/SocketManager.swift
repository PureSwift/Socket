//
//  SocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage
import Atomics

/// Socket Manager
internal final class SocketManager {
    
    static let shared = SocketManager()
    
    private var didSetup = false
    
    private var sockets = [SocketState]()
    
    private var runloop: CFRunLoop?
    
    private var source: CFRunLoopSource?
            
    private var lock = NSLock()
    
    deinit {
        removeRunloop()
    }
    
    private init() {
        // Add to runloop of background thread from concurrency thread pool
        Task(priority: .high) { [unowned self] in
            self.addRunloop()
        }
    }
    
    func add(_ socket: Socket) {
        let id = ObjectIdentifier(socket)
        let state = SocketState(
            id: id,
            fileDescriptor: socket.fileDescriptor,
            socket: .passUnretained(socket)
        )
        // append lock
        lock.lock()
        sockets.append(state)
        lock.unlock()
    }
    
    func remove(_ socket: Socket) {
        let id = ObjectIdentifier(socket)
        lock.lock()
        defer { lock.unlock() }
        guard let index = sockets.firstIndex(where: { $0.id == id }) else {
            assertionFailure()
            return
        }
        sockets.remove(at: index)
        
    }
    
    func queueWrite(_ data: Data, for socket: Socket) {
        lock.lock()
        defer { lock.unlock() }
        
    }
    
    /// Setup runloop  once
    private func addRunloop() {
        guard didSetup == false else { return }
        var context = CFRunLoopSourceContext()
        context.perform = SocketManagerPerform
        context.info = Unmanaged<SocketManager>
            .passUnretained(self)
            .toOpaque()
        
        let source = CFRunLoopSourceCreate(nil, 0, &context)
        let runloop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runloop, source, .defaultMode)
        self.source = source
        self.runloop = runloop
        self.didSetup = true
    }
    
    private func removeRunloop() {
        guard didSetup, let runloop = runloop, let source = source else { return }
        CFRunLoopRemoveSource(runloop, source, .defaultMode)
    }
    
    internal func poll() {
        var pollDescriptors = sockets
            .lazy
            .map { $0.socket.takeUnretainedValue().fileDescriptor }
            .map { FileDescriptor.Poll(fileDescriptor: $0, events: .socket) }
        
        do {
            try pollDescriptors.poll()
        }
        catch {
            log("SocketManager.poll(): \(error.localizedDescription)")
            return
        }
        
        for poll in pollDescriptors {
            guard poll.returnedEvents.isEmpty == false else { return }
            sockets
                .lazy
                .map { $0.takeUnretainedValue() }
                .filter { $0.fileDescriptor == poll.fileDescriptor }
                .forEach { $0.didPoll(poll.returnedEvents) }
        }
    }
}

// MARK: - Supporting Types

extension SocketManager {
    
    struct SocketState {
        
        let id: ObjectIdentifier
        
        let fileDescriptor: FileDescriptor
        
        let socket: Unmanaged<Socket>
        
        var hasPendingWrites = false
    }
}

// MARK: - C Callbacks

@_silgen_name("swift_socket_manager_perform")
internal func SocketManagerPerform(_ pointer: UnsafeMutableRawPointer?) {
    assert(Thread.isMainThread)
    guard let pointer = pointer else {
        assertionFailure()
        return
    }
    let manager = Unmanaged<SocketManager>
        .fromOpaque(pointer)
        .takeUnretainedValue()
    manager.poll()
}
