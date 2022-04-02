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
    
    weak var delegate: SocketManagerDelegate?
    
    private var didSetup = false
    
    private var sockets = [FileDescriptor: SocketState]()
    
    private var pollDescriptors = [FileDescriptor.Poll]()
    
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
        lock.lock()
        sockets[fileDescriptor] = nil
        updatePollDescriptors()
        lock.unlock()
    }
    
    func write(_ data: Data, for fileDescriptor: FileDescriptor) {
        lock.lock()
        assert(sockets[fileDescriptor] == nil)
        sockets[fileDescriptor]?.pendingWrites.append(data)
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
    
    private func updatePollDescriptors() {
        pollDescriptors = sockets.keys
            .lazy
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { FileDescriptor.Poll(fileDescriptor: $0, events: .socket) }
    }
    
    internal func poll() {
        lock.lock()
        defer { lock.unlock() }
        do {
            try pollDescriptors.poll()
        }
        catch {
            log("SocketManager.poll(): \(error.localizedDescription)")
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
                error(Errno.badFileDescriptor, for: fileDescriptor)
            }
            if fileEvents.contains(.hangup) {
                error(Errno.connectionAbort, for: fileDescriptor)
            }
            if fileEvents.contains(.error) {
                error(Errno.connectionReset, for: fileDescriptor)
            }
        }
    }
    
    private func error(_ error: Error, for fileDescriptor: FileDescriptor) {
        delegate?.socket(fileDescriptor, error: error)
    }
    
    private func shouldRead(_ fileDescriptor: FileDescriptor) {
        guard let _ = self.sockets[fileDescriptor]
            else { return }
        let bytesToRead = delegate?.socketShouldRead(fileDescriptor) ?? 0
        guard bytesToRead > 0 else { return }
        var data = Data(count: Int(bytesToRead))
        do {
            let bytesRead = try data.withUnsafeMutableBytes {
                try fileDescriptor.read(into: $0)
            }
            if bytesRead < bytesToRead {
                data = data.prefix(bytesRead)
            }
            delegate?.socket(fileDescriptor, didRead: .success(data))
        } catch {
            delegate?.socket(fileDescriptor, didRead: .failure(error))
        }
    }
    
    private func canWrite(_ fileDescriptor: FileDescriptor) {
        guard let socket = self.sockets[fileDescriptor],
            socket.pendingWrites.isEmpty == false
            else { return }
        let pendingData = socket.pendingWrites.removeFirst()
        //
        Task(priority: .high) {
            do {
                let byteCount = try pendingData.withUnsafeBytes {
                    try fileDescriptor.write($0)
                }
                delegate?.socket(fileDescriptor, didWrite: .success(byteCount))
            }
            catch {
                delegate?.socket(fileDescriptor, didWrite: .failure(error))
            }
        }
    }
}

// MARK: - Supporting Types

protocol SocketManagerDelegate: AnyObject {
    
    func socket(_ fileDescriptor: FileDescriptor, didWrite write: Result<Int, Error>)
    
    func socketShouldRead(_ fileDescriptor: FileDescriptor) -> UInt
    
    func socket(_ fileDescriptor: FileDescriptor, didRead read: Result<Data, Error>)
    
    func socket(_ fileDescriptor: FileDescriptor, error: Error)
}

extension SocketManager {
    
    final class SocketState {
                
        let fileDescriptor: FileDescriptor
        
        init(fileDescriptor: FileDescriptor) {
            self.fileDescriptor = fileDescriptor
        }
        
        var pendingWrites = [Data]()
        
        var isWriting = false
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
