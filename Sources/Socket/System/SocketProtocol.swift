
/// POSIX Socket Protocol
public protocol SocketProtocol: RawRepresentable, Sendable {
    
    static var family: SocketAddressFamily { get }
    
    var type: SocketType { get }
    
    init?(rawValue: Int32)
    
    var rawValue: Int32 { get }
}
