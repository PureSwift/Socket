//
//  CFSocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/12/23.
//

import Foundation
import CoreFoundation

///
public struct CFSocketConfiguration: SocketManagerConfiguration {
    
    public var log: ((String) -> ())?
    
    public init(
        log: ((String) -> Void)? = nil
    ) {
        self.log = log
    }
    
    public static var manager: some SocketManager {
        CFSocketManager.shared
    }
    
    public func configureManager() {
        Task {
            await CFSocketManager.shared.setConfiguration(self)
        }
    }
}

internal actor CFSocketManager: SocketManager {
    
    // MARK: - Properties
    
    var configuration = CFSocketConfiguration()
    
    var sockets = [SocketDescriptor: SocketState]()
    
    // MARK: - Initialization
    
    static let shared = CFSocketManager()
    
    init() { }
    
    // MARK: - Methods
    
    func setConfiguration(_ newValue: CFSocketConfiguration) {
        self.configuration = newValue
    }
    
    /// Add file descriptor
    func add(
        _ fileDescriptor: SocketDescriptor
    ) -> Socket.Event.Stream {
        let event = Socket.Event.Stream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            
        }
        return event
    }
    
    /// Remove file descriptor
    func remove(
        _ fileDescriptor: SocketDescriptor,
        error: Error?
    ) {
        
    }
    
    /// Write data to managed file descriptor.
    func write(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        fatalError()
    }
    
    /// Read managed file descriptor.
    func read(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        fatalError()
    }
    
    func receiveMessage(
        _ length: Int,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Data {
        fatalError()
    }
    
    func receiveMessage<Address: SocketAddress>(
        _ length: Int,
        fromAddressOf addressType: Address.Type,
        for fileDescriptor: SocketDescriptor
    ) async throws -> (Data, Address) {
        fatalError()
    }
    
    func sendMessage(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        fatalError()
    }
    
    func sendMessage<Address: SocketAddress>(
        _ data: Data,
        to address: Address,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        fatalError()
    }
}

extension CFSocketManager {
    
    struct SocketState {
        
        let fileDescriptor: SocketDescriptor
        
        let event: Socket.Event.Stream.Continuation
        
        let socket: CFSocket
    }
}

private extension CFSocketManager {
    
    #if DEBUG
    static let debugLogEnabled = ProcessInfo.processInfo.environment["SWIFTSOCKETDEBUG"] == "1"
    #endif
    
    func log(_ message: String) {
        if let logger = configuration.log {
            logger(message)
        } else {
            #if DEBUG
            if CFSocketManager.debugLogEnabled {
                NSLog("Socket: " + message)
            }
            #endif
        }
    }
}
