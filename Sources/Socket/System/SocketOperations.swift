import SystemPackage

extension SocketDescriptor {
    
    /// Creates an endpoint for communication and returns a descriptor.
    ///
    /// - Parameters:
    ///   - protocolID: The protocol which will be used for communication.
    ///   - retryOnInterrupt: Whether to retry the read operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The file descriptor of the opened socket.
    ///
    @_alwaysEmitIntoClient
    public init<T: SocketProtocol>(
        _ protocolID: T,
        retryOnInterrupt: Bool = true
    ) throws {
        self = try Self._socket(T.family, type: protocolID.type.rawValue, protocol: protocolID.rawValue, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    #if os(Linux)
    /// Creates an endpoint for communication and returns a descriptor.
    ///
    /// - Parameters:
    ///   - protocolID: The protocol which will be used for communication.
    ///   - flags: Flags to set when opening the socket.
    ///   - retryOnInterrupt: Whether to retry the read operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The file descriptor of the opened socket.
    ///
    @_alwaysEmitIntoClient
    public init<T: SocketProtocol>(
        _ protocolID: T,
        flags: SocketFlags,
        retryOnInterrupt: Bool = true
    ) throws {
        self = try Self._socket(T.family, type: protocolID.type.rawValue | flags.rawValue, protocol: protocolID.rawValue, retryOnInterrupt: retryOnInterrupt).get()
    }
    #endif
    
    @usableFromInline
    internal static func _socket(
        _ family: SocketAddressFamily,
        type: CInt,
        protocol protocolID: Int32,
        retryOnInterrupt: Bool
    ) -> Result<SocketDescriptor, Errno> {
        valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
            system_socket(family.rawValue, type, protocolID)
        }.map({ SocketDescriptor(rawValue: $0) })
    }
    
    /// Creates an endpoint for communication and returns a descriptor.
    ///
    /// - Parameters:
    ///   - protocolID: The protocol which will be used for communication.
    ///   - flags: Flags to set when opening the socket.
    ///   - retryOnInterrupt: Whether to retry the read operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The file descriptor of the opened socket.
    ///
    @_alwaysEmitIntoClient
    public init<Address: SocketAddress>(
        _ protocolID: Address.ProtocolID,
        bind address: Address,
        retryOnInterrupt: Bool = true
    ) throws {
        self = try Self._socket(
            address: address,
            type: protocolID.type.rawValue,
            protocol: protocolID.rawValue,
            retryOnInterrupt: retryOnInterrupt
        ).get()
    }
    
    #if os(Linux)
    /// Creates an endpoint for communication and returns a descriptor.
    ///
    /// - Parameters:
    ///   - protocolID: The protocol which will be used for communication.
    ///   - flags: Flags to set when opening the socket.
    ///   - retryOnInterrupt: Whether to retry the read operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The file descriptor of the opened socket.
    ///
    @_alwaysEmitIntoClient
    public init<Address: SocketAddress>(
        _ protocolID: Address.ProtocolID,
        bind address: Address,
        flags: SocketFlags,
        retryOnInterrupt: Bool = true
    ) throws {
        self = try Self._socket(
            address: address,
            type: protocolID.type.rawValue | flags.rawValue,
            protocol: protocolID.rawValue,
            retryOnInterrupt: retryOnInterrupt
        ).get()
    }
    #endif
    
    @usableFromInline
    internal static func _socket<Address: SocketAddress>(
        address: Address,
        type: CInt,
        protocol protocolID: Int32,
        retryOnInterrupt: Bool
    ) -> Result<SocketDescriptor, Errno> {
        return _socket(
            Address.family,
            type: type,
            protocol: protocolID,
            retryOnInterrupt: retryOnInterrupt
        )._closeIfThrows { fileDescriptor in
            fileDescriptor
                ._bind(address, retryOnInterrupt: retryOnInterrupt)
                .map { fileDescriptor }
        }
    }
    
    /// Assigns the address specified to the socket referred to by the file descriptor.
    ///
    ///  - Parameter address: Specifies the address to bind the socket.
    ///  - Parameter retryOnInterrupt: Whether to retry the open operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    ///
    /// The corresponding C function is `bind`.
    @_alwaysEmitIntoClient
    public func bind<Address: SocketAddress>(
        _ address: Address,
        retryOnInterrupt: Bool = true
    ) throws {
        try _bind(address, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    @usableFromInline
    internal func _bind<T: SocketAddress>(
        _ address: T,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            address.withUnsafePointer { (addressPointer, length) in
                system_bind(rawValue, addressPointer, length)
            }
        }
    }
    
    /// Set the option specified for the socket associated with the file descriptor.
    ///
    ///  - Parameter option: Socket option value to set.
    ///  - Parameter retryOnInterrupt: Whether to retry the open operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    ///
    /// The method corresponds to the C function `setsockopt`.
    @_alwaysEmitIntoClient
    public func setSocketOption<T: SocketOption>(
        _ option: T,
        retryOnInterrupt: Bool = true
    ) throws {
        try _setSocketOption(option, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    @usableFromInline
    internal func _setSocketOption<T: SocketOption>(
        _ option: T,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            option.withUnsafeBytes { bufferPointer in
                system_setsockopt(self.rawValue, T.ID.optionLevel.rawValue, T.id.rawValue, bufferPointer.baseAddress!, UInt32(bufferPointer.count))
            }
        }
    }
    
    ///  Retrieve the value associated with the option specified for the socket associated with the file descriptor.
    ///
    ///  - Parameter option: Type of `SocketOption` to retrieve.
    ///  - Parameter retryOnInterrupt: Whether to retry the open operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    ///
    /// The method corresponds to the C function `getsockopt`.
    @_alwaysEmitIntoClient
    public func getSocketOption<T: SocketOption>(
        _ option: T.Type,
        retryOnInterrupt: Bool = true
    ) throws -> T {
        return try _getSocketOption(option, retryOnInterrupt: retryOnInterrupt)
    }
    
    @usableFromInline
    internal func _getSocketOption<T: SocketOption>(
        _ option: T.Type,
        retryOnInterrupt: Bool
    ) throws -> T {
        return try T.withUnsafeBytes { bufferPointer in
            var length = UInt32(bufferPointer.count)
            guard system_getsockopt(self.rawValue, T.ID.optionLevel.rawValue, T.id.rawValue, bufferPointer.baseAddress!, &length) != -1 else {
                throw Errno.current
            }
        }
    }
    
    /// Send a message from a socket.
    ///
    /// - Parameters:
    ///   - buffer: The region of memory that contains the data being sent.
    ///   - flags: see `send(2)`
    ///   - retryOnInterrupt: Whether to retry the send operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were sent.
    ///
    /// The corresponding C function is `send`.
    @_alwaysEmitIntoClient
    public func send(
      _ buffer: UnsafeRawBufferPointer,
      flags: MessageFlags = [],
      retryOnInterrupt: Bool = true
    ) throws -> Int {
      try _send(buffer, flags: flags, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    /// Send a message from a socket.
    ///
    /// - Parameters:
    ///   - data: The sequence of bytes being sent.
    ///   - address: Address of destination client.
    ///   - flags: see `send(2)`
    ///   - retryOnInterrupt: Whether to retry the send operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were sent.
    ///
    /// The corresponding C function is `send`.
    public func send<Data>(
        _ data: Data,
        flags: MessageFlags = [],
        retryOnInterrupt: Bool = true
    ) throws -> Int where Data: Sequence, Data.Element == UInt8 {
        try data._withRawBufferPointer { dataPointer in
            _send(dataPointer, flags: flags, retryOnInterrupt: retryOnInterrupt)
        }.get()
    }

    @usableFromInline
    internal func _send(
      _ buffer: UnsafeRawBufferPointer,
      flags: MessageFlags,
      retryOnInterrupt: Bool
    ) -> Result<Int, Errno> {
      valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
        system_send(self.rawValue, buffer.baseAddress, buffer.count, flags.rawValue)
      }
    }
    
    /// Send a message from a socket.
    ///
    /// - Parameters:
    ///   - buffer: The region of memory that contains the data being sent.
    ///   - address: Address of destination client.
    ///   - flags: see `sendto(2)`
    ///   - retryOnInterrupt: Whether to retry the send operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were sent.
    ///
    /// The corresponding C function is `sendto`.
    @_alwaysEmitIntoClient
    public func send<Address: SocketAddress>(
        _ buffer: UnsafeRawBufferPointer,
        to address: Address,
        flags: MessageFlags = [],
        retryOnInterrupt: Bool = true
    ) throws -> Int {
        try _sendto(buffer, to: address, flags: flags, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    /// Send a message from a socket.
    ///
    /// - Parameters:
    ///   - data: The sequence of bytes being sent.
    ///   - address: Address of destination client.
    ///   - flags: see `sendto(2)`
    ///   - retryOnInterrupt: Whether to retry the send operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were sent.
    ///
    /// The corresponding C function is `sendto`.
    public func send<Address, Data>(
        _ data: Data,
        to address: Address,
        flags: MessageFlags = [],
        retryOnInterrupt: Bool = true
    ) throws -> Int where Address: SocketAddress, Data: Sequence, Data.Element == UInt8 {
        try data._withRawBufferPointer { dataPointer in
            _sendto(dataPointer, to: address, flags: flags, retryOnInterrupt: retryOnInterrupt)
        }.get()
    }
    
    /// `sendto()`
    @usableFromInline
    internal func _sendto<Address: SocketAddress>(
        _ data: UnsafeRawBufferPointer,
        to address: Address,
        flags: MessageFlags,
        retryOnInterrupt: Bool
    ) -> Result<Int, Errno> {
        valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
            address.withUnsafePointer { (addressPointer, addressLength) in
                system_sendto(self.rawValue, data.baseAddress, data.count, flags.rawValue, addressPointer, addressLength)
            }
        }
    }
    
    /// Receive a message from a socket.
    ///
    /// - Parameters:
    ///   - buffer: The region of memory to receive into.
    ///   - flags: see `recv(2)`
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were received.
    ///
    /// The corresponding C function is `recv`.
    @_alwaysEmitIntoClient
    public func receive(
      into buffer: UnsafeMutableRawBufferPointer,
      flags: MessageFlags = [],
      retryOnInterrupt: Bool = true
    ) throws -> Int {
      try _receive(
        into: buffer, flags: flags, retryOnInterrupt: retryOnInterrupt
      ).get()
    }

    @usableFromInline
    internal func _receive(
      into buffer: UnsafeMutableRawBufferPointer,
      flags: MessageFlags,
      retryOnInterrupt: Bool
    ) -> Result<Int, Errno> {
      valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
        system_recv(self.rawValue, buffer.baseAddress, buffer.count, flags.rawValue)
      }
    }
    
    /// Receive a message from a socket.
    ///
    /// - Parameters:
    ///   - buffer: The region of memory to receive into.
    ///   - address: The address the message was sent from
    ///   - flags: see `recvfrom(2)`
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were received.
    ///
    /// The corresponding C function is `recvfrom`.
    @_alwaysEmitIntoClient
    public func receive<Address: SocketAddress>(
      into buffer: UnsafeMutableRawBufferPointer,
      fromAddressOf addressType: Address.Type = Address.self,
      flags: MessageFlags = [],
      retryOnInterrupt: Bool = true
    ) throws -> (Int, Address) {
      try _receivefrom(
        into: buffer, fromAddressOf: addressType, flags: flags, retryOnInterrupt: retryOnInterrupt
      ).get()
    }
    
    @usableFromInline
    internal func _receivefrom<Address: SocketAddress>(
      into buffer: UnsafeMutableRawBufferPointer,
      fromAddressOf addressType: Address.Type = Address.self,
      flags: MessageFlags,
      retryOnInterrupt: Bool
    ) -> Result<(Int, Address), Errno> {
      var result: Result<Int, Errno> = .success(0)
      let address = Address.withUnsafePointer { addressPointer, addressLength in
        var length = addressLength
        result = valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
          system_recvfrom(self.rawValue, buffer.baseAddress, buffer.count, flags.rawValue, addressPointer, &length)
        }
      }
      return result.map { ($0, address) }
    }
    
    /// Listen for connections on a socket.
    ///
    /// Only applies to sockets of connection type `.stream`.
    ///
    /// - Parameters:
    ///   - backlog: the maximum length for the queue of pending connections
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    ///
    /// The corresponding C function is `listen`.
    @_alwaysEmitIntoClient
    public func listen(
        backlog: Int,
        retryOnInterrupt: Bool = true
    ) throws {
        try _listen(backlog: Int32(backlog), retryOnInterrupt: retryOnInterrupt).get()
    }
    
    @usableFromInline
    internal func _listen(
        backlog: Int32,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            system_listen(self.rawValue, backlog)
        }
    }
    
    /// Accept a connection on a socket.
    ///
    /// - Parameters:
    ///   - address: The type of the `SocketAddress` expected for the new connection.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: A tuple containing the file descriptor and address of the new connection.
    ///
    /// The corresponding C function is `accept`.
    @_alwaysEmitIntoClient
    public func accept<Address: SocketAddress>(
        _ address: Address.Type,
        retryOnInterrupt: Bool = true
    ) throws -> (SocketDescriptor, Address) {
        return try _accept(address, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    @usableFromInline
    internal func _accept<Address: SocketAddress>(
        _ address: Address.Type,
        retryOnInterrupt: Bool
    ) -> Result<(SocketDescriptor, Address), Errno> {
        var result: Result<CInt, Errno> = .success(0)
        let address = Address.withUnsafePointer { socketPointer, socketLength in
            var length = socketLength
            result = valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
                system_accept(self.rawValue, socketPointer, &length)
            }
        }
        return result.map { (SocketDescriptor(rawValue: $0), address) }
    }
    
    /// Accept a connection on a socket.
    ///
    /// - Parameters:
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The file descriptor of the new connection.
    ///
    /// The corresponding C function is `accept`.
    @_alwaysEmitIntoClient
    public func accept(
        retryOnInterrupt: Bool = true
    ) throws -> SocketDescriptor {
        return try _accept(retryOnInterrupt: retryOnInterrupt).get()
    }
    
    @usableFromInline
    internal func _accept(
        retryOnInterrupt: Bool
    ) -> Result<SocketDescriptor, Errno> {
        var length: UInt32 = 0
        return valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
            system_accept(self.rawValue, nil, &length)
        }.map(SocketDescriptor.init(rawValue:))
    }
    
    /// Initiate a connection on a socket.
    ///
    /// - Parameters:
    ///   - address: The peer address.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The file descriptor of the new connection.
    ///
    /// The corresponding C function is `connect`.
    @_alwaysEmitIntoClient
    public func connect<Address: SocketAddress>(
        to address: Address,
        retryOnInterrupt: Bool = true
    ) throws {
        try _connect(to: address, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    /// The `connect()` function shall attempt to make a connection on a socket.
    @usableFromInline
    internal func _connect<Address: SocketAddress>(
        to address: Address,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            address.withUnsafePointer { (addressPointer, addressLength) in
                system_connect(self.rawValue, addressPointer, addressLength)
            }
        }
    }
    
    /// Deletes a file descriptor.
    ///
    /// Deletes the file descriptor from the per-process object reference table.
    /// If this is the last reference to the underlying object,
    /// the object will be deactivated.
    ///
    /// The corresponding C function is `close`.
    @_alwaysEmitIntoClient
    public func close() throws { try _close().get() }

    @usableFromInline
    internal func _close() -> Result<(), Errno> {
      nothingOrErrno(retryOnInterrupt: false) { system_close(self.rawValue) }
    }
    
    
    /// Reads bytes at the current file offset into a buffer.
    ///
    /// - Parameters:
    ///   - buffer: The region of memory to read into.
    ///   - retryOnInterrupt: Whether to retry the read operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were read.
    ///
    /// The <doc://com.apple.documentation/documentation/swift/unsafemutablerawbufferpointer/3019191-count> property of `buffer`
    /// determines the maximum number of bytes that are read into that buffer.
    ///
    /// After reading,
    /// this method increments the file's offset by the number of bytes read.
    /// To change the file's offset,
    /// call the ``seek(offset:from:)`` method.
    ///
    /// The corresponding C function is `read`.
    @_alwaysEmitIntoClient
    public func read(
      into buffer: UnsafeMutableRawBufferPointer,
      retryOnInterrupt: Bool = true
    ) throws -> Int {
      try _read(into: buffer, retryOnInterrupt: retryOnInterrupt).get()
    }

    @usableFromInline
    internal func _read(
      into buffer: UnsafeMutableRawBufferPointer,
      retryOnInterrupt: Bool
    ) -> Result<Int, Errno> {
      valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
        system_read(self.rawValue, buffer.baseAddress, buffer.count)
      }
    }
    
    /// Writes the contents of a buffer at the current file offset.
    ///
    /// - Parameters:
    ///   - buffer: The region of memory that contains the data being written.
    ///   - retryOnInterrupt: Whether to retry the write operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    /// - Returns: The number of bytes that were written.
    ///
    /// After writing,
    /// this method increments the file's offset by the number of bytes written.
    /// To change the file's offset,
    /// call the ``seek(offset:from:)`` method.
    ///
    /// The corresponding C function is `write`.
    @_alwaysEmitIntoClient
    public func write(
      _ buffer: UnsafeRawBufferPointer,
      retryOnInterrupt: Bool = true
    ) throws -> Int {
      try _write(buffer, retryOnInterrupt: retryOnInterrupt).get()
    }

    @usableFromInline
    internal func _write(
      _ buffer: UnsafeRawBufferPointer,
      retryOnInterrupt: Bool
    ) -> Result<Int, Errno> {
      valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
        system_write(self.rawValue, buffer.baseAddress, buffer.count)
      }
    }
    
    @_alwaysEmitIntoClient
    public func address<Address: SocketAddress>(
        _ address: Address.Type,
        retryOnInterrupt: Bool = true
    ) throws -> Address {
        return try _getAddress(address, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    @usableFromInline
    internal func _getAddress<Address: SocketAddress>(
        _ address: Address.Type,
        retryOnInterrupt: Bool
    ) -> Result<Address, Errno> {
        var result: Result<CInt, Errno> = .success(0)
        let address = Address.withUnsafePointer { socketPointer, socketLength in
            var length = socketLength
            result = valueOrErrno(retryOnInterrupt: retryOnInterrupt) {
                system_getsockname(self.rawValue, socketPointer, &length)
            }
        }
        return result.map { _ in address }
    }
}
