//
//  Socket.swift
//
//
//  Created by Alsey Coleman Miller on 4/1/22.
//

import Foundation
import Dispatch
import SystemPackage

/// Socket
public final class Socket {
    
    private static let queue = DispatchQueue(label: "org.pureswift.socket", qos: .userInteractive, attributes: .concurrent)
    
    private let stream: DispatchIO
    
    public init(fileDescriptor: FileDescriptor) async throws {
        self.stream = try await .open(stream: fileDescriptor.rawValue, queue: Self.queue)
    }
}
