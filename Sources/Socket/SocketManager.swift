//
//  SocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import SystemPackage

/// Socket Manager
public protocol SocketManager: AnyObject {
    
    /// Add file descriptor
    func add(
        _ fileDescriptor: SocketDescriptor
    ) async -> Socket.Event.Stream
    
    /// Remove file descriptor
    func remove(
        _ fileDescriptor: SocketDescriptor,
        error: Error?
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
}

/// Socket Manager Configuration
public protocol SocketManagerConfiguration {
    
    associatedtype Manager: SocketManager
    
    /// Manager
    static var manager: Manager { get }
    
    func configureManager()
}
