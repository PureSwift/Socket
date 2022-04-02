//
//  SocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage

internal actor SocketManager {
    
    static let shared = SocketManager()
    
    private var didSetup = false
    
    private var sockets = [ObjectIdentifier: Unmanaged<Socket>]()
        
    private var runloop: CFRunLoop?
    
    private var source: CFRunLoopSource?
    
    deinit {
        removeRunloop()
    }
    
    private init() {
        addRunloop()
    }
    
    func add(_ socket: Socket) {
        lock.lock()
        // pass as unowned reference
        let id = ObjectIdentifier(socket)
        sockets[id] = Unmanaged.passUnretained(socket)
        lock.unlock()
    }
    
    func remove(_ socket: Socket) {
        lock.lock()
        let id = ObjectIdentifier(socket)
        sockets[id] = nil
        lock.unlock()
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
        let runloop = CFRunLoopGetMain()
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
        lock.lock()
        defer { lock.unlock() }
        
        var pollDescriptors = sockets
            .lazy
            .sorted(by: { $0.key < $1.key })
            .map { $0.value.takeUnretainedValue().fileDescriptor }
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
                .values
                .lazy
                .map { $0.takeUnretainedValue() }
                .filter { $0.fileDescriptor == poll.fileDescriptor }
                .forEach { socket in
                    socket.didPoll(poll.returnedEvents)
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
