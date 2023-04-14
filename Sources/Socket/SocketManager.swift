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
    ) async
    
    /// Remove file descriptor
    func remove(
        _ fileDescriptor: SocketDescriptor,
        error: Error?
    ) async
    
    /// Wait for events.
    func wait(
        for event: FileEvents,
        fileDescriptor: SocketDescriptor
    ) async throws
    
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

public extension SocketManager {
    
    func wait(
        for event: FileEvents,
        fileDescriptor: SocketDescriptor
    ) async throws {
        
    }
    
    /// Write data to managed file descriptor.
    func write(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        try await wait(for: [.write], fileDescriptor: fileDescriptor)
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.write($0)
        }
        return byteCount
    }
    
    /// Read managed file descriptor.
    func read(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        try await wait(for: [.read], fileDescriptor: fileDescriptor)
        var data = Data(count: length)
        let bytesRead = try data.withUnsafeMutableBytes {
            try fileDescriptor.read(into: $0)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        return data
    }
    
    func receiveMessage(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        var data = Data(count: length)
        let bytesRead = try data.withUnsafeMutableBytes {
            try fileDescriptor.receive(into: $0)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        return data
    }
    
    func receiveMessage<Address: SocketAddress>(
        _ length: Int,
        fromAddressOf addressType: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (Data, Address) {
        var data = Data(count: length)
        let (bytesRead, address) = try data.withUnsafeMutableBytes {
            try fileDescriptor.receive(into: $0, fromAddressOf: addressType)
        }
        if bytesRead < length {
            data = data.prefix(bytesRead)
        }
        return (data, address)
    }
    
    func sendMessage(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        try await wait(for: [.write], fileDescriptor: fileDescriptor)
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0)
        }
        return byteCount
    }
    
    func sendMessage<Address: SocketAddress>(
        _ data: Data,
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        try await wait(for: [.write], fileDescriptor: fileDescriptor)
        let byteCount = try data.withUnsafeBytes {
            try fileDescriptor.send($0, to: address)
        }
        return byteCount
    }
}

/// Socket Manager Configuration
public protocol SocketManagerConfiguration {
    
    associatedtype Manager: SocketManager
    
    /// Manager
    static var manager: Manager { get }
    
    func configureManager()
}
