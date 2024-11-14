//
//  SocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage

/// Socket Manager
public protocol SocketManager: AnyObject, Sendable {
    
    /// Add file descriptor
    func add(
        _ fileDescriptor: SocketDescriptor
    ) async -> Socket.Event.Stream
    
    /// Remove file descriptor
    func remove(
        _ fileDescriptor: SocketDescriptor
    ) async
    
    /// Write data to managed file descriptor.
    func write(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int
    
    /// Read managed file descriptor.
    func read(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data
    
    func receiveMessage(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data
    
    func receiveMessage<Address: SocketAddress>(
        _ length: Int,
        fromAddressOf addressType: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (Data, Address)
    
    func sendMessage(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int
    
    func sendMessage<Address: SocketAddress>(
        _ data: Data,
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int
    
    /// Accept new socket.
    func accept(
        for fileDescriptor: SocketDescriptor
    ) async throws -> SocketDescriptor
    
    /// Accept a connection on a socket.
    func accept<Address: SocketAddress>(
        _ address: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (fileDescriptor: SocketDescriptor, address: Address)
    
    /// Initiate a connection on a socket.
    func connect<Address: SocketAddress>(
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws
    
    /// Listen for incoming connections
    func listen(
        backlog: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws
}

/// Socket Manager Configuration
public protocol SocketManagerConfiguration: Sendable {
    
    associatedtype Manager: SocketManager
    
    /// Manager
    static var manager: Manager { get }
    
    func configureManager()
}
