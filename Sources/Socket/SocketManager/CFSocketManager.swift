//
//  CFSocketManager.swift
//  
//
//  Created by Alsey Coleman Miller on 4/12/23.
//

#if canImport(Darwin)
import Foundation
@preconcurrency import CoreFoundation
import Dispatch

///
internal struct CFSocketConfiguration {
    
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
    
    //public static var manager: some SocketManager
    /*
    public func configureManager() {
        Task {
            await CFSocketManager.shared.setConfiguration(self)
        }
    }*/
}

internal actor CFSocketManager {
    
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
    ) async -> Socket.Event.Stream {
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
        self.sockets[fileDescriptor] = SocketState(
            fileDescriptor: fileDescriptor,
            socket: socket,
            source: source
        )
        // add to queue run loop
        configuration.queue.async {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
        }
        fatalError()
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
    
    func wait(for event: FileEvents, fileDescriptor: SocketDescriptor) async throws {
        
    }
}

internal func CFSocketManagerCallback(
    socket: CFSocket!,
    callbackType: CFSocketCallBackType,
    data: CFData!,
    info: UnsafeRawPointer!,
    context: UnsafeMutableRawPointer!
) {
    //let manager: CFSocketManager = Unmanaged.fromOpaque(context).takeUnretainedValue()
    
    
}

extension CFSocketManager {
    
    struct SocketState {
        
        let fileDescriptor: SocketDescriptor
                
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

#endif
