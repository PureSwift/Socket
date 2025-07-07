import SystemPackage

#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import CSocket
import ucrt
#elseif canImport(Glibc)
import CSocket
import Glibc
#elseif canImport(Musl)
import CSocket
import Musl
#elseif canImport(WASILibc)
import CSocket
import WASILibc
#elseif canImport(Bionic)
import CSocket
import Bionic
#else
#error("Unsupported Platform")
#endif

/// A namespace for C and platform types
public extension CInterop {
    
    /// The platform file descriptor set.
    typealias FileDescriptorSet = fd_set
  
    typealias PollFileDescriptor = pollfd
  
    typealias FileDescriptorCount = nfds_t
  
    typealias FileEvent = Int16
    
    #if os(Windows)
    /// The platform socket descriptor.
    typealias SocketDescriptor = SOCKET
    #else
    /// The platform socket descriptor, which is the same as a file desciptor on Unix systems.
    typealias SocketDescriptor = CInt
    #endif

    /// The C `msghdr` type
     typealias MessageHeader = msghdr
  
    /// The C `sa_family_t` type
     typealias SocketAddressFamily = sa_family_t

    /// Socket Type
    #if os(Linux)
    typealias SocketType = __socket_type
    #else
    typealias SocketType = CInt
    #endif
    
    /// The C `addrinfo` type
    typealias AddressInfo = addrinfo
    
    /// The C `in_addr` type
    typealias IPv4Address = in_addr
    
    /// The C `in6_addr` type
    typealias IPv6Address = in6_addr
    
    /// The C `sockaddr_in` type
    typealias SocketAddress = sockaddr
    
    #if !os(Android)
    /// The C `sockaddr_in` type
    typealias UnixSocketAddress = sockaddr_un
    #endif
  
    /// The C `sockaddr_in` type
    typealias IPv4SocketAddress = sockaddr_in
    
    /// The C `sockaddr_in6` type
    typealias IPv6SocketAddress = sockaddr_in6
    
    #if canImport(Darwin)
    /// The C `sockaddr_dl` type
    typealias LinkLayerAddress = sockaddr_dl
    #elseif os(Linux)
    /// The C `sockaddr_ll` type
    typealias LinkLayerAddress = sockaddr_ll
    #endif
    
    /// The C `if_nameindex` type
    typealias InterfaceNameIndex = if_nameindex
    
    /// The C  `ifaddrs` type
    typealias InterfaceLinkedList = ifaddrs
    
    typealias IOControlID = CUnsignedLong
}
