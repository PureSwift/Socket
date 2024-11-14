import SystemPackage

#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import CSystem
import ucrt
#elseif canImport(Glibc)
@_implementationOnly import CSystem
import Glibc
#elseif canImport(Musl)
@_implementationOnly import CSystem
import Musl
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(Bionic)
@_implementationOnly import CSystem
import Bionic
#else
#error("Unsupported Platform")
#endif

@inline(__always)
internal var mockingEnabled: Bool {
  // Fast constant-foldable check for release builds
  #if ENABLE_MOCKING
    return contextualMockingEnabled
  #else
    return false
  #endif
}


#if ENABLE_MOCKING
// Strip the mock_system prefix and the arg list suffix
private func originalSyscallName(_ function: String) -> String {
  // `function` must be of format `system_<name>(<parameters>)`
  precondition(function.starts(with: "system_"))
  return String(function.dropFirst("system_".count).prefix { $0 != "(" })
}

private func mockImpl(
  name: String,
  path: UnsafePointer<CInterop.PlatformChar>?,
  _ args: [AnyHashable]
) -> CInt {
  precondition(mockingEnabled)
  let origName = originalSyscallName(name)
  guard let driver = currentMockingDriver else {
    fatalError("Mocking requested from non-mocking context")
  }
  var mockArgs: Array<AnyHashable> = []
  if let p = path {
    mockArgs.append(String(_errorCorrectingPlatformString: p))
  }
  mockArgs.append(contentsOf: args)
  driver.trace.add(Trace.Entry(name: origName, mockArgs))

  switch driver.forceErrno {
  case .none: break
  case .always(let e):
    system_errno = e
    return -1
  case .counted(let e, let count):
    assert(count >= 1)
    system_errno = e
    driver.forceErrno = count > 1 ? .counted(errno: e, count: count-1) : .none
    return -1
  }

  return 0
}

internal func _mock(
  name: String = #function, path: UnsafePointer<CInterop.PlatformChar>? = nil, _ args: AnyHashable...
) -> CInt {
  return mockImpl(name: name, path: path, args)
}
internal func _mockInt(
  name: String = #function, path: UnsafePointer<CInterop.PlatformChar>? = nil, _ args: AnyHashable...
) -> Int {
  Int(mockImpl(name: name, path: path, args))
}

#endif // ENABLE_MOCKING

#if canImport(Darwin)
internal var system_errno: CInt {
  get { Darwin.errno }
  set { Darwin.errno = newValue }
}
#elseif os(Windows)
internal var system_errno: CInt {
  get {
    var value: CInt = 0
    // TODO(compnerd) handle the error?
    _ = ucrt._get_errno(&value)
    return value
  }
  set {
    _ = ucrt._set_errno(newValue)
  }
}
#else
internal var system_errno: CInt {
  get { Glibc.errno }
  set { Glibc.errno = newValue }
}
#endif

// close
internal func system_close(_ fd: Int32) -> Int32 {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd) }
#endif
  return close(fd)
}

// write
internal func system_write(
  _ fd: Int32, _ buf: UnsafeRawPointer!, _ nbyte: Int
) -> Int {
#if ENABLE_MOCKING
  if mockingEnabled { return _mockInt(fd, buf, nbyte) }
#endif
  return write(fd, buf, nbyte)
}

// read
internal func system_read(
  _ fd: Int32, _ buf: UnsafeMutableRawPointer!, _ nbyte: Int
) -> Int {
#if ENABLE_MOCKING
  if mockingEnabled { return _mockInt(fd, buf, nbyte) }
#endif
  return read(fd, buf, nbyte)
}

internal func system_inet_pton(
    _ family: Int32,
    _ cString: UnsafePointer<CInterop.PlatformChar>,
    _ address: UnsafeMutableRawPointer) -> Int32 {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(family, cString, address) }
  #endif
  return inet_pton(family, cString, address)
}

internal func system_inet_ntop(_ family: Int32, _ pointer : UnsafeRawPointer, _ string: UnsafeMutablePointer<CChar>, _ length: UInt32) -> UnsafePointer<CChar>? {
  #if ENABLE_MOCKING
  //if mockingEnabled { return _mock(family, pointer, string, length) }
  #endif
  return inet_ntop(family, pointer, string, length)
}

internal func system_socket(_ fd: Int32, _ fd2: Int32, _ fd3: Int32) -> Int32 {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, fd2, fd3) }
  #endif
  return socket(fd, fd2, fd3)
}

internal func system_setsockopt(_ fd: Int32, _ fd2: Int32, _ fd3: Int32, _ pointer: UnsafeRawPointer, _ dataLength: UInt32) -> Int32 {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, fd2, fd3, pointer, dataLength) }
  #endif
  return setsockopt(fd, fd2, fd3, pointer, dataLength)
}

internal func system_getsockopt(
  _ socket: CInt,
  _ level: CInt,
  _ option: CInt,
  _ value: UnsafeMutableRawPointer?,
  _ length: UnsafeMutablePointer<UInt32>?
) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(socket, level, option, value, length) }
  #endif
  return getsockopt(socket, level, option, value, length)
}

internal func system_bind(
    _ socket: CInt,
    _ address: UnsafePointer<CInterop.SocketAddress>,
    _ length: UInt32
) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(socket, address, length) }
  #endif
  return bind(socket, address, length)
}

internal func system_connect(
  _ socket: CInt,
  _ addr: UnsafePointer<sockaddr>?,
  _ len: socklen_t
) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(socket, addr, len) }
  #endif
  return connect(socket, addr, len)
}

internal func system_accept(
  _ socket: CInt,
  _ addr: UnsafeMutablePointer<sockaddr>?,
  _ len: UnsafeMutablePointer<socklen_t>?
) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(socket, addr, len) }
  #endif
  return accept(socket, addr, len)
}

internal func system_getaddrinfo(
  _ hostname: UnsafePointer<CChar>?,
  _ servname: UnsafePointer<CChar>?,
  _ hints: UnsafePointer<CInterop.AddressInfo>?,
  _ res: UnsafeMutablePointer<UnsafeMutablePointer<CInterop.AddressInfo>?>?
) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled {
    return _mock(hostname,
                 servname,
                 hints, res)
  }
  #endif
  return getaddrinfo(hostname, servname, hints, res)
}

internal func system_getnameinfo(
  _ sa: UnsafePointer<CInterop.SocketAddress>?,
  _ salen: UInt32,
  _ host: UnsafeMutablePointer<CChar>?,
  _ hostlen: UInt32,
  _ serv: UnsafeMutablePointer<CChar>?,
  _ servlen: UInt32,
  _ flags: CInt
) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled {
    return _mock(sa, salen, host, hostlen, serv, servlen, flags)
  }
  #endif
  return getnameinfo(sa, salen, host, hostlen, serv, servlen, flags)
}

internal func system_freeaddrinfo(
  _ addrinfo: UnsafeMutablePointer<CInterop.AddressInfo>?
) {
  #if ENABLE_MOCKING
  if mockingEnabled {
    _ = _mock(addrinfo)
    return
  }
  #endif
  return freeaddrinfo(addrinfo)
}

internal func system_gai_strerror(_ error: CInt) -> UnsafePointer<CChar> {
  #if ENABLE_MOCKING
  // FIXME
  #endif
  return gai_strerror(error)
}

internal func system_shutdown(_ socket: CInt, _ how: CInt) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(socket, how) }
  #endif
  return shutdown(socket, how)
}

internal func system_listen(_ socket: CInt, _ backlog: CInt) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(socket, backlog) }
  #endif
  return listen(socket, backlog)
}

internal func system_send(
  _ socket: Int32, _ buffer: UnsafeRawPointer?, _ len: Int, _ flags: Int32
) -> Int {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mockInt(socket, buffer, len, flags) }
  #endif
  return send(socket, buffer, len, flags)
}

internal func system_recv(
  _ socket: Int32,
  _ buffer: UnsafeMutableRawPointer?,
  _ len: Int,
  _ flags: Int32
) -> Int {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mockInt(socket, buffer, len, flags) }
  #endif
  return recv(socket, buffer, len, flags)
}

internal func system_sendto(
  _ socket: CInt,
  _ buffer: UnsafeRawPointer?,
  _ length: Int,
  _ flags: CInt,
  _ dest_addr: UnsafePointer<CInterop.SocketAddress>?,
  _ dest_len: UInt32
) -> Int {
  #if ENABLE_MOCKING
  if mockingEnabled {
    return _mockInt(socket, buffer, length, flags, dest_addr, dest_len)
  }
  #endif
  return sendto(socket, buffer, length, flags, dest_addr, dest_len)
}

internal func system_recvfrom(
  _ socket: CInt,
  _ buffer: UnsafeMutableRawPointer?,
  _ length: Int,
  _ flags: CInt,
  _ address: UnsafeMutablePointer<CInterop.SocketAddress>?,
  _ addres_len: UnsafeMutablePointer<UInt32>?
) -> Int {
  #if ENABLE_MOCKING
  if mockingEnabled {
    return _mockInt(socket, buffer, length, flags, address, addres_len)
  }
  #endif
  return recvfrom(socket, buffer, length, flags, address, addres_len)
}

internal func system_poll(
    _ fileDescriptors: UnsafeMutablePointer<CInterop.PollFileDescriptor>,
    _ fileDescriptorsCount: CInterop.FileDescriptorCount,
    _ timeout: CInt
) -> CInt {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mock(fileDescriptors, fileDescriptorsCount, timeout) }
  #endif
  return poll(fileDescriptors, fileDescriptorsCount, timeout)
}

internal func system_sendmsg(
  _ socket: CInt,
  _ message: UnsafePointer<CInterop.MessageHeader>?,
  _ flags: CInt
) -> Int {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mockInt(socket, message, flags) }
  #endif
  return sendmsg(socket, message, flags)
}

internal func system_recvmsg(
  _ socket: CInt,
  _ message: UnsafeMutablePointer<CInterop.MessageHeader>?,
  _ flags: CInt
) -> Int {
  #if ENABLE_MOCKING
  if mockingEnabled { return _mockInt(socket, message, flags) }
  #endif
  return recvmsg(socket, message, flags)
}

internal func system_fcntl(
  _ fd: Int32,
  _ cmd: Int32
) -> CInt {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, cmd) }
#endif
  return fcntl(fd, cmd)
}

internal func system_fcntl(
  _ fd: Int32,
  _ cmd: Int32,
  _ value: Int32
) -> CInt {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, cmd, value) }
#endif
  return fcntl(fd, cmd, value)
}

internal func system_fcntl(
  _ fd: Int32,
  _ cmd: Int32,
  _ pointer: UnsafeMutableRawPointer
) -> CInt {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, cmd, pointer) }
#endif
  return fcntl(fd, cmd, pointer)
}

// ioctl
internal func system_ioctl(
  _ fd: Int32,
  _ request: CUnsignedLong
) -> CInt {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, request) }
#endif
  return ioctl(fd, request)
}

// ioctl
internal func system_ioctl(
  _ fd: Int32,
  _ request: CUnsignedLong,
  _ value: CInt
) -> CInt {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, request, value) }
#endif
  return ioctl(fd, request, value)
}

// ioctl
internal func system_ioctl(
  _ fd: Int32,
  _ request: CUnsignedLong,
  _ pointer: UnsafeMutableRawPointer
) -> CInt {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(fd, request, pointer) }
#endif
  return ioctl(fd, request, pointer)
}

// if_nameindex
internal func system_if_nameindex() -> UnsafeMutablePointer<CInterop.InterfaceNameIndex>? {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock() }
#endif
    return if_nameindex()
}

// if_nameindex
internal func system_if_freenameindex(_ pointer: UnsafeMutablePointer<CInterop.InterfaceNameIndex>?) {
#if ENABLE_MOCKING
  if mockingEnabled { return _mock(pointer) }
#endif
    return if_freenameindex(pointer)
}

internal func system_getifaddrs(_ pointer: UnsafeMutablePointer<UnsafeMutablePointer<CInterop.InterfaceLinkedList>?>) -> CInt {
#if ENABLE_MOCKING
    if mockingEnabled { return _mock(pointer) }
#endif
    return getifaddrs(pointer)
}

internal func system_freeifaddrs(_ pointer: UnsafeMutablePointer<CInterop.InterfaceLinkedList>?) {
#if ENABLE_MOCKING
    if mockingEnabled { return _mock(pointer) }
#endif
    return freeifaddrs(pointer)
}

#if canImport(Darwin)
internal func system_link_addr(_ cString: UnsafePointer<CChar>, _ address: UnsafeMutablePointer<sockaddr_dl>) {
#if ENABLE_MOCKING
    if mockingEnabled { return _mock(cString) }
#endif
    return link_addr(cString, address)
}

internal func system_link_ntoa(_ address: UnsafePointer<sockaddr_dl>) -> UnsafeMutablePointer<CChar> {
#if ENABLE_MOCKING
    if mockingEnabled { return _mock(cString) }
#endif
    return link_ntoa(address)
}
#endif

internal func system_getsockname(_ fd: CInt, _ address: UnsafeMutablePointer<CInterop.SocketAddress>, _ length: UnsafeMutablePointer<UInt32>) -> CInt {
#if ENABLE_MOCKING
    if mockingEnabled { return _mock(fd, address) }
#endif
    return getsockname(fd, address, length)
}

internal func system_getpeername(_ fd: CInt, _ address: UnsafeMutablePointer<CInterop.SocketAddress>, _ length: UnsafeMutablePointer<UInt32>) -> CInt {
#if ENABLE_MOCKING
    if mockingEnabled { return _mock(fd, address) }
#endif
    return getpeername(fd, address, length)
}
