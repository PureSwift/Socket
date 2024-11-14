import SystemPackage

@usableFromInline
internal protocol CInternetAddress {
    
    static var stringLength: Int { get }
    
    static var family: SocketAddressFamily { get }
    
    init()
}

internal extension CInternetAddress {
    
    @usableFromInline
    init?(_ string: String) {
        self.init()
        /**
         inet_pton() returns 1 on success (network address was successfully converted). 0 is returned if src does not contain a character string representing a valid network address in the specified address family. If af does not contain a valid address family, -1 is returned and errno is set to EAFNOSUPPORT.
        */
        let result = string.withCString { cString in
            withUnsafeMutableBytes(of: &self) { buffer in
                system_inet_pton(Self.family.rawValue, cString, buffer.baseAddress!)
            }
        }
        guard result == 1 else {
            assert(result != -1, "Invalid address family")
            return nil
        }
    }
}

internal extension String {
    
    @usableFromInline
    init<T: CInternetAddress>(_ cInternetAddress: T) throws(Errno) {
        let cString = UnsafeMutablePointer<CChar>.allocate(capacity: T.stringLength)
        defer { cString.deallocate() }
        let success = withUnsafePointer(to: cInternetAddress) {
            system_inet_ntop(
                T.family.rawValue,
                $0,
                cString,
                numericCast(T.stringLength)
            ) != nil
        }
        guard success else {
            throw Errno.current
        }
        
        self.init(cString: cString)
    }
}

extension CInterop.IPv4Address: CInternetAddress {
    
    @usableFromInline
    static var stringLength: Int { return numericCast(_INET_ADDRSTRLEN) }
    
    @usableFromInline
    static var family: SocketAddressFamily { .ipv4 }
}

extension CInterop.IPv6Address: CInternetAddress {
    
    @usableFromInline
    static var stringLength: Int { return numericCast(_INET6_ADDRSTRLEN) }
    
    @usableFromInline
    static var family: SocketAddressFamily { .ipv6 }
}
