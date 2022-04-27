//
//  IPv6SocketAddress.swift
//
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

/// IPv6 Protocol Family
public enum IPv6Protocol: Int32, Codable, SocketProtocol {
    
    case raw
    case tcp
    case udp
    
    @_alwaysEmitIntoClient
    public static var family: SocketAddressFamily { .ipv6 }
    
    @_alwaysEmitIntoClient
    public var type: SocketType {
        switch self {
        case .raw: return .raw
        case .tcp: return .stream
        case .udp: return .datagram
        }
    }
    
    @_alwaysEmitIntoClient
    public var rawValue: Int32 {
        switch self {
        case .raw: return _IPPROTO_RAW
        case .tcp: return _IPPROTO_TCP
        case .udp: return _IPPROTO_UDP
        }
    }
}
