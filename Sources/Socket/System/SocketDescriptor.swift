//
//  SocketDescriptor.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

import SystemPackage

/// Native Socket handle.
///
/// Same as ``FileDescriptor`` on POSIX and opaque type on Windows.
public struct SocketDescriptor: RawRepresentable, Equatable, Hashable, Sendable {
    
    public typealias RawValue = CInterop.SocketDescriptor
    
    public let rawValue: RawValue
    
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
}
