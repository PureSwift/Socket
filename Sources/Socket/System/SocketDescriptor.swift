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
    
    #if os(Windows)
    #error("Implement Windows support")
    /// Native Windows Socket handle
    ///
    /// https://docs.microsoft.com/en-us/windows/win32/api/winsock2/
    public typealias RawValue = CInterop.WinSock
    #else
    /// Native POSIX Socket handle
    public typealias RawValue = FileDescriptor.RawValue
    #endif
    
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
    
    public let rawValue: RawValue
}
