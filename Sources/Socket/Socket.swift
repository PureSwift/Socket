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
    
    /// Configuration for fine-tuning socket performance.
    public static var configuration = Socket.Configuration()
    
    /// Underlying file descriptor
    public let fileDescriptor: FileDescriptor
    
    public let event: Socket.Event.Stream
    
    internal unowned let manager: SocketManager
    
    // MARK: - Initialization
    
    /// Starts monitoring a socket.
    public init(
        fileDescriptor: FileDescriptor
    ) async {
        let manager = SocketManager.shared
        self.fileDescriptor = fileDescriptor
        self.manager = manager
        self.event = await manager.add(fileDescriptor)
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
    
    public func close() async {
        await manager.remove(fileDescriptor)
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

public extension Socket.Event {
    
    typealias Stream = AsyncStream<Socket.Event>
}

public extension Socket {
    
    struct Configuration {
        
        public var log: ((String) -> ())?
        
        /// Task priority for backgroud socket polling.
        public var monitorPriority: TaskPriority = .medium
        
        /// Interval in nanoseconds for monitoring / polling socket.
        public var monitorInterval: UInt64 = 100_000_000
    }
}
