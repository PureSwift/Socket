//
//  Socket.swift
//
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
@_exported import SystemPackage

/// Socket
public struct Socket {
    
    // MARK: - Properties
    
    /// Configuration for fine-tuning socket performance.
    public static var configuration: AsyncSocketConfiguration = AsyncSocketConfiguration() {
        didSet {
            configuration.configureManager()
        }
    }
    
    /// Underlying native socket handle.
    public let fileDescriptor: SocketDescriptor
    
    public let event: Socket.Event.Stream
    
    internal unowned let manager: SocketManager
    
    // MARK: - Initialization
    
    /// Starts monitoring a socket.
    public init(
        fileDescriptor: SocketDescriptor
    ) async {
        let manager = type(of: Self.configuration).manager
        await self.init(
            fileDescriptor: fileDescriptor,
            manager: manager
        )
    }
    
    internal init(
        fileDescriptor: SocketDescriptor,
        manager: SocketManager
    ) async {
        self.fileDescriptor = fileDescriptor
        self.manager = manager
        self.event = await manager.add(fileDescriptor)
    }
    
    /// Initialize
    public init<T: SocketProtocol>(
        _ protocolID: T
    ) async throws {
        let fileDescriptor = try SocketDescriptor(protocolID)
        await self.init(fileDescriptor: fileDescriptor)
    }
    
    ///
    public init<Address: SocketAddress>(
        _ protocolID: Address.ProtocolID,
        bind address: Address
    ) async throws {
        let fileDescriptor = try SocketDescriptor(protocolID, bind: address)
        await self.init(fileDescriptor: fileDescriptor)
    }
    
    #if os(Linux)
    ///
    public init<T: SocketProtocol>(
        _ protocolID: T,
        flags: SocketFlags
    ) async throws {
        let fileDescriptor = try SocketDescriptor(protocolID, flags: flags)
        await self.init(fileDescriptor: fileDescriptor)
    }
    
    ///
    public init<Address: SocketAddress>(
        _ protocolID: Address.ProtocolID,
        bind address: Address,
        flags: SocketFlags
    ) async throws {
        let fileDescriptor = try SocketDescriptor(protocolID, bind: address, flags: flags)
        await self.init(fileDescriptor: fileDescriptor)
    }
    #endif
    
    // MARK: - Methods
    
    /// Close socket.
    public func close() async {
        await manager.remove(fileDescriptor)
    }
    
    /// Write to socket
    @discardableResult
    public func write(_ data: Data) async throws -> Int {
        try await manager.write(data, for: fileDescriptor)
    }
    
    /// Send message to socket
    @discardableResult
    public func sendMessage(_ data: Data) async throws -> Int {
        try await manager.sendMessage(data, for: fileDescriptor)
    }
    
    /// Send message to socket
    @discardableResult
    public func sendMessage<Address: SocketAddress>(_ data: Data, to address: Address) async throws -> Int {
        try await manager.sendMessage(data, to: address, for: fileDescriptor)
    }
    
    /// Read from socket
    public func read(_ length: Int) async throws -> Data {
        try await manager.read(length, for: fileDescriptor)
    }
    
    /// Receive message from socket
    public func receiveMessage(_ length: Int) async throws -> Data {
        try await manager.receiveMessage(length, for: fileDescriptor)
    }
    
    /// Receive message from socket
    public func receiveMessage<Address: SocketAddress>(_ length: Int, fromAddressOf addressType: Address.Type = Address.self) async throws -> (Data, Address) {
        try await manager.receiveMessage(length, fromAddressOf: addressType, for: fileDescriptor)
    }
    
    /// Get socket option.
    public subscript <T: SocketOption> (_ option: T.Type) -> T {
        get throws {
            return try fileDescriptor.getSocketOption(option)
        }
    }
    
    /// Set socket option.
    public func setOption <T: SocketOption> (_ option: T) throws {
        try fileDescriptor.setSocketOption(option)
    }
    
    /// Listen for connections on a socket.
    public func listen(backlog: Int = Self.maxSocketBacklog) async throws {
        try await manager.listen(backlog: backlog, for: fileDescriptor)
    }
    
    /// Accept new socket.
    public func accept() async throws -> Socket {
        let newConnection = try await manager.accept(for: fileDescriptor)
        return await Socket(fileDescriptor: newConnection, manager: manager)
    }
    
    /// Accept a connection on a socket.
    public func accept<Address: SocketAddress>(_ address: Address.Type) async throws -> (socket: Socket, address: Address) {
        let newConnection = try await manager.accept(address, for: fileDescriptor)
        let socket = await Socket(fileDescriptor: newConnection.fileDescriptor, manager: manager)
        return (socket, newConnection.address)
    }
    
    /// Initiate a connection on a socket.
    public func connect<Address: SocketAddress>(to address: Address) async throws {
        try await manager.connect(to: address, for: fileDescriptor)
    }
}

// MARK: - Constants

public extension Socket {
    
    /// Maximum queue length specifiable by listen.
    static var maxSocketBacklog: Int {
        Int(_SOMAXCONN)
    }
}

// MARK: - Supporting Types

public extension Socket {
    
    /// Socket Event
    enum Event {
        
        /// New connection
        case connection
        
        /// Pending read
        case read
        
        /// Pending Write
        case write
        
        /// Did read
        case didRead(Int)
        
        /// Did write
        case didWrite(Int)
        
        /// Error ocurred
        case error(Error)
        
        /// Socket closed
        case close
    }
}

public extension Socket.Event {
    
    /// Socket Event Stream
    typealias Stream = AsyncStream<Socket.Event>
}
