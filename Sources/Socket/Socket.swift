//
//  Socket.swift
//
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage
import Atomics

/// Socket
public final class Socket {
    
    // MARK: - Properties
    
    /// Underlying file descriptor
    public let fileDescriptor: FileDescriptor
    
    internal let event: ((Event) -> ())
        
    // MARK: - Initialization
    
    deinit {
        // remove from global manager
        DispatchQueue.main.sync { [unowned self] in
            SocketManager.shared.remove(self)
        }
        
        // close
        do {
            try fileDescriptor.close()
        }
        catch {
            log("Unable to close socket \(fileDescriptor)")
        }
    }
        
    public init(
        fileDescriptor: FileDescriptor,
        event: @escaping (Event) -> () = { _ in }
    ) {
        self.fileDescriptor = fileDescriptor
        self.event = event
        
        // make sure its non blocking
        do { try setNonBlock() }
        catch {
            log("Unable to set non blocking. \(error)")
            assertionFailure("Unable to set non blocking. \(error)")
            return
        }
        
        // schedule on global manager
        DispatchQueue.main.async { [unowned self] in
            SocketManager.shared.add(self)
        }
    }
    
    // MARK: - Methods
    
    public func write(_ data: Data) async throws {
        DispatchQueue.main.async { [unowned self] in
            SocketManager.shared.queueWrite(data, for: self)
        }
    }
        
    internal func didPoll(_ fileEvents: FileEvents) {
        if fileEvents.contains(.read) ||
            fileEvents.contains(.readUrgent) {
            shouldRead()
        }
        if fileEvents.contains(.write) {
            canWrite()
        }
        if fileEvents.contains(.error) ||
            fileEvents.contains(.invalidRequest) ||
            fileEvents.contains(.hangup) {
            didError()
        }
    }
    
    private func shouldRead() {
        
    }
    
    private func canWrite() {
        let fileDescriptor = self.fileDescriptor
        guard hasPendingWrite.load(ordering: .sequentiallyConsistent),
              isWriting.load(ordering: .relaxed) == false else { return }
        isWriting.store(true, ordering: .relaxed)
        Task(priority: priority) {
            guard let pendingData = await storage.dequeueWrite() else { return }
            try pendingData.withUnsafeBytes {
                do { try fileDescriptor.write($0) }
                catch Errno.wouldBlock { }
            }
        }
    }
    
    private func didError() {
        
    }
    
    private func setNonBlock() throws {
        var status = try fileDescriptor.getStatus()
        if status.contains(.nonBlocking) == false {
            status.insert(.nonBlocking)
            try fileDescriptor.setStatus(status)
        }
    }
}

// MARK: - Supporting Types

public extension Socket {
    
    /// Socket Event
    enum Event {
        case read(Data)
        case write(Data)
        case close(Error?)
    }
}

internal extension Socket {
    
    actor Storage {
        
        var pendingWrites = [Data]()
        
        func queueWrite(_ data: Data) {
            pendingWrites.append(data)
        }
        
        func dequeueWrite() -> Data? {
            guard pendingWrites.isEmpty == false else {
                return nil
            }
            return pendingWrites.removeFirst()
        }
    }
}

