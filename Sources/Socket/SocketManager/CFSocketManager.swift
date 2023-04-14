//
//  CFSocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/12/23.
//

import Foundation
import CoreFoundation
import Dispatch

///
public struct CFSocketConfiguration: SocketManagerConfiguration {
    
    public var log: ((String) -> ())?
    
    public var queue: DispatchQueue = .main
    
    public var timeout: CFTimeInterval = 30
    
    public init(
        log: ((String) -> Void)? = nil,
        queue: DispatchQueue = .main,
        timeout: CFTimeInterval = 30
    ) {
        self.log = log
        self.queue = queue
        self.timeout = timeout
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
    
    fileprivate func setConfiguration(_ newValue: CFSocketConfiguration) {
        self.configuration = newValue
    }
    
    /// Add file descriptor
    func add(
        _ fileDescriptor: SocketDescriptor
    ) -> Socket.Event.Stream {
        guard sockets.keys.contains(fileDescriptor) == false else {
            fatalError("Another socket for file descriptor \(fileDescriptor) already exists.")
        }
        log("Add socket \(fileDescriptor)")
        // make sure its non blocking
        do {
            var status = try fileDescriptor.getStatus()
            if status.contains(.nonBlocking) == false {
                status.insert(.nonBlocking)
                try fileDescriptor.setStatus(status)
            }
        }
        catch {
            log("Unable to set non blocking. \(error)")
            assertionFailure("Unable to set non blocking. \(error)")
        }
        // create CFSocket
        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = CFSocketContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
        let callbacks: CFSocketCallBackType = [.readCallBack, .writeCallBack, .acceptCallBack, .connectCallBack]
        guard let socket = CFSocketCreateWithNative(nil, fileDescriptor.rawValue, CFOptionFlags(callbacks.rawValue), CFSocketManagerCallback, &context) else {
            fatalError("Unable to create socket")
        }
        let source = CFSocketCreateRunLoopSource(nil, socket, 0)!
        let event = Socket.Event.Stream(bufferingPolicy: .bufferingNewest(10)) { continuation in
            self.sockets[fileDescriptor] = SocketState(
                fileDescriptor: fileDescriptor,
                event: continuation,
                socket: socket,
                source: source
            )
        }
        // add to queue run loop
        configuration.queue.async {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
        }
        return event
    }
    
    /// Remove file descriptor
    func remove(
        _ fileDescriptor: SocketDescriptor,
        error: Error?
    ) {
        guard let socketState = sockets[fileDescriptor] else {
            return
        }
        log("Remove socket \(fileDescriptor) \(error?.localizedDescription ?? "")")
        // close underlying socket
        CFRunLoopSourceInvalidate(socketState.source)
        CFSocketInvalidate(socketState.socket)
        // update sockets to monitor
        sockets[fileDescriptor] = nil
    }
    
    /// Write data to managed file descriptor.
    func write(
        _ data: Data,
        for fileDescriptor: SocketDescriptor
    ) async throws -> Int {
        guard let socketState = sockets[fileDescriptor] else {
            throw Errno.badFileDescriptor
        }
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

internal func CFSocketManagerCallback(
    socket: CFSocket!,
    callbackType: CFSocketCallBackType,
    data: CFData!,
    info: UnsafeRawPointer!,
    pointer: UnsafeMutableRawPointer!
) {
    
}

extension CFSocketManager {
    
    struct SocketState {
        
        let fileDescriptor: SocketDescriptor
        
        let event: Socket.Event.Stream.Continuation
        
        let socket: CFSocket
        
        let source: CFRunLoopSource
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
