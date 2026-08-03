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
    
    #if os(Linux) || os(Android) || canImport(Darwin)
    /// Send a message carrying file descriptors as `SCM_RIGHTS` ancillary data.
    func sendMessage<T: DataProtocol>(
        _ data: T,
        fileDescriptors: [SocketDescriptor],
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int
    
    /// Receive a message along with any `SCM_RIGHTS` file descriptors that accompany it.
    func receiveMessage(
        _ length: Int,
        maximumDescriptors: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> SocketMessage
    #endif
    
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


#if os(Linux) || os(Android) || canImport(Darwin)
public extension SocketManager {
    
    /// File descriptor passing is optional; a manager that does not implement it reports so.
    func sendMessage<T: DataProtocol>(
        _ data: T,
        fileDescriptors: [SocketDescriptor],
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        throw Errno.notSupported
    }
    
    /// File descriptor passing is optional; a manager that does not implement it reports so.
    func receiveMessage(
        _ length: Int,
        maximumDescriptors: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> SocketMessage {
        throw Errno.notSupported
    }
}
#endif
