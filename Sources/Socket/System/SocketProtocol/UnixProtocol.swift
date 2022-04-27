//
//  UnixProtocol.swift
//
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

/// Unix Protocol Family
public enum UnixProtocol: Int32, Codable, SocketProtocol {
    
    case raw = 0
    
    @_alwaysEmitIntoClient
    public static var family: SocketAddressFamily { .unix }
    
    @_alwaysEmitIntoClient
    public var type: SocketType {
        switch self {
        case .raw: return .raw
        }
    }
}
