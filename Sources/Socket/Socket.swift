//
//  Socket.swift
//
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage

/// Socket
public struct Socket {
    
    // MARK: - Properties
    
    /// Underlying file descriptor
    public let fileDescriptor: FileDescriptor
    
    internal unowned let manager: SocketManager
    
    // MARK: - Initialization
    
    /// Starts monitoring a socket.
    public init(
        fileDescriptor: FileDescriptor,
        event: ((Event) -> ())? = nil
    ) {
        let manager = SocketManager.shared
        self.fileDescriptor = fileDescriptor
        self.manager = manager
        
        // make sure its non blocking
        do { try setNonBlock() }
        catch {
            log("Unable to set non blocking. \(error)")
            assertionFailure("Unable to set non blocking. \(error)")
            return
        }
        
        // start monitoring
        Task {
            await manager.add(fileDescriptor: fileDescriptor, event: event)
        }
    }
    
    // MARK: - Methods
    
    /// Write to socket
    @discardableResult
    public func write(_ data: Data) async throws -> Int {
        try await manager.write(data, for: fileDescriptor)
    }
    
    /// Read from socket
    public func read(_ length: Int) async throws -> Data {
        try await manager.read(length, for: fileDescriptor)
    }
    
    public func close() {
        Task {
            await manager.remove(fileDescriptor)
        }
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
        case pendingRead
        case read(Int)
        case write(Int)
        case close(Error?)
    }
}
