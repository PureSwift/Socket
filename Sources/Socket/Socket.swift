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
    public static var configuration: any SocketManagerConfiguration = AsyncSocketConfiguration() {
        didSet {
            configuration.configureManager()
        }
    }
    
    /// Underlying native socket handle.
    public let fileDescriptor: SocketDescriptor
    
    internal unowned let manager: SocketManager
    
    // MARK: - Initialization
    
    /// Starts monitoring a socket.
    public init(
        fileDescriptor: SocketDescriptor
    ) async {
        self.fileDescriptor = fileDescriptor
        self.manager = type(of: Self.configuration).manager
        await manager.add(fileDescriptor)
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
        await manager.remove(fileDescriptor, error: nil)
    }
    
    /// Suspend the current task until the specied events are ready.
    public func wait(for events: FileEvents) async throws {
        try await manager.wait(for: events, fileDescriptor: fileDescriptor)
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
}
