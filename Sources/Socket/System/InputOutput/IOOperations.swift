import SystemPackage

extension SocketDescriptor {
    
    /// Manipulates the underlying device parameters of special files.
    @_alwaysEmitIntoClient
    public func inputOutput<T: IOControlID>(
        _ request: T,
        retryOnInterrupt: Bool = true
    ) throws(Errno) {
        try _inputOutput(request, retryOnInterrupt: true).get()
    }
    
    /// Manipulates the underlying device parameters of special files.
    @usableFromInline
    internal func _inputOutput<T: IOControlID>(
        _ request: T,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            system_ioctl(self.rawValue, request.rawValue)
        }
    }
    
    /// Manipulates the underlying device parameters of special files.
    @_alwaysEmitIntoClient
    public func inputOutput<T: IOControlInteger>(
        _ request: T,
        retryOnInterrupt: Bool = true
    ) throws(Errno) {
        try _inputOutput(request, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    /// Manipulates the underlying device parameters of special files.
    @usableFromInline
    internal func _inputOutput<T: IOControlInteger>(
        _ request: T,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            system_ioctl(self.rawValue, T.id.rawValue, request.intValue)
        }
    }
    
    /// Manipulates the underlying device parameters of special files.
    @_alwaysEmitIntoClient
    public func inputOutput<T: IOControlValue>(
        _ request: inout T,
        retryOnInterrupt: Bool = true
    ) throws(Errno) {
        try _inputOutput(&request, retryOnInterrupt: retryOnInterrupt).get()
    }
    
    /// Manipulates the underlying device parameters of special files.
    @usableFromInline
    internal func _inputOutput<T: IOControlValue>(
        _ request: inout T,
        retryOnInterrupt: Bool
    ) -> Result<(), Errno> {
        nothingOrErrno(retryOnInterrupt: retryOnInterrupt) {
            request.withUnsafeMutablePointer { pointer in
                system_ioctl(self.rawValue, T.id.rawValue, pointer)
            }
        }
    }
}
