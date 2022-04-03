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
public struct Socket {
    
    // MARK: - Properties
    
    /// Underlying file descriptor
    public let fileDescriptor: FileDescriptor
        
    internal unowned let manager: SocketManager
        
    // MARK: - Initialization
    
    public init(
        fileDescriptor: FileDescriptor
    ) {
        self.fileDescriptor = fileDescriptor
        self.manager = SocketManager.shared
        
        // make sure its non blocking
        do { try setNonBlock() }
        catch {
            log("Unable to set non blocking. \(error)")
            assertionFailure("Unable to set non blocking. \(error)")
            return
        }
        
        manager.add(fileDescriptor)
    }
    
    // MARK: - Methods
    
    public func write(_ data: Data) async throws {
        try await manager.write(data, for: fileDescriptor)
    }
    
    public func read(_ length: Int) async throws -> Data {
        try await manager.read(length, for: fileDescriptor)
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
