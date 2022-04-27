import SystemPackage

#if swift(>=5.5)
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public extension SocketDescriptor {
    
    /// Accept a connection on a socket.
    ///
    /// - Parameters:
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    ///   - sleep: The number of nanoseconds to sleep if the operation
    ///     throws ``Errno/wouldBlock`` or other async I/O errors..
    /// - Returns: The file descriptor of the new connection.
    ///
    /// The corresponding C function is `accept`.
    @_alwaysEmitIntoClient
    func accept(
        retryOnInterrupt: Bool = true,
        sleep: UInt64 = 10_000_000
    ) async throws -> SocketDescriptor {
        try await retry(sleep: sleep) {
            _accept(retryOnInterrupt: retryOnInterrupt)
        }.get()
    }
    
    /// Accept a connection on a socket.
    ///
    /// - Parameters:
    ///   - address: The type of the `SocketAddress` expected for the new connection.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    ///   - sleep: The number of nanoseconds to sleep if the operation
    ///     throws ``Errno/wouldBlock`` or other async I/O errors.
    /// - Returns: A tuple containing the file descriptor and address of the new connection.
    ///
    /// The corresponding C function is `accept`.
    @_alwaysEmitIntoClient
    func accept<Address: SocketAddress>(
        _ address: Address.Type,
        retryOnInterrupt: Bool = true,
        sleep: UInt64 = 10_000_000
    ) async throws -> (SocketDescriptor, Address) {
        try await retry(sleep: sleep) {
            _accept(address, retryOnInterrupt: retryOnInterrupt)
        }.get()
    }
    
    /// Initiate a connection on a socket.
    ///
    /// - Parameters:
    ///   - address: The peer address.
    ///   - retryOnInterrupt: Whether to retry the receive operation
    ///     if it throws ``Errno/interrupted``.
    ///     The default is `true`.
    ///     Pass `false` to try only once and throw an error upon interruption.
    ///   - sleep: The number of nanoseconds to sleep if the operation
    ///     throws ``Errno/wouldBlock`` or other async I/O errors.
    /// - Returns: The file descriptor of the new connection.
    ///
    /// The corresponding C function is `connect`.
    @_alwaysEmitIntoClient
    func connect<Address: SocketAddress>(
        to address: Address,
        retryOnInterrupt: Bool = true,
        sleep: UInt64 = 10_000_000
    ) async throws {
        try await retry(sleep: sleep) {
            _connect(to: address, retryOnInterrupt: retryOnInterrupt)
        }.get()
    }
}

#endif
