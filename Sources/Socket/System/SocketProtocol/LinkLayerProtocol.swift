//
//  LinkLayerProtocol.swift
//  
//
//  Created by Alsey Coleman Miller on 10/1/22.
//

#if canImport(Darwin) || os(Linux)
/// Unix Protocol Family
public enum LinkLayerProtocol: Int32, Codable, SocketProtocol {
    
    case raw = 0
    
    @_alwaysEmitIntoClient
    public static var family: SocketAddressFamily {
        #if canImport(Darwin)
        .link
        #elseif os(Linux)
        .packet
        #else
        #error("Unsupported platform")
        #endif
    }
    
    @_alwaysEmitIntoClient
    public var type: SocketType {
        switch self {
        case .raw: return .raw
        }
    }
}
#endif
