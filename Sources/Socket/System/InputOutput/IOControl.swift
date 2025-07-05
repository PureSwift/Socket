/// Input / Output Request identifier for manipulating underlying device parameters of special files.
public protocol IOControlID: RawRepresentable {
    
    /// Create a strongly-typed I/O request from a raw C IO request.
    init?(rawValue: CInterop.IOControlID)
    
    /// The raw C IO request ID.
    var rawValue: CInterop.IOControlID { get }
}

public protocol IOControlInteger {
    
    associatedtype ID: IOControlID
    
    static var id: ID { get }
    
    var intValue: Int32 { get }
}

public protocol IOControlValue {
    
    associatedtype ID: IOControlID
    
    static var id: ID { get }
    
    mutating func withUnsafeMutablePointer<Result>(_ body: (UnsafeMutableRawPointer) throws -> (Result)) rethrows -> Result
}

#if os(Linux)
public extension IOControlID {
    
    init?(type: IOType, direction: IODirection, code: CInt, size: CInt) {
        self.init(rawValue: _IOC(direction, type, code, size))
    }
}

/// #define _IOC(dir,type,nr,size) \
/// (((dir)  << _IOC_DIRSHIFT) | \
/// ((type) << _IOC_TYPESHIFT) | \
/// ((nr)   << _IOC_NRSHIFT) | \
/// ((size) << _IOC_SIZESHIFT))
@usableFromInline
internal func _IOC(
    _ direction: IODirection,
    _ type: IOType,
    _ nr: CInt,
    _ size: CInt
) -> CUnsignedLong {
    
    let dir = CInt(direction.rawValue)
    let dirValue = dir << _DIRSHIFT
    let typeValue = type.rawValue << _TYPESHIFT
    let nrValue = nr << _NRSHIFT
    let sizeValue = size << _SIZESHIFT
    let value = CLong(dirValue | typeValue | nrValue | sizeValue)
    return CUnsignedLong(bitPattern: value)
}

@_alwaysEmitIntoClient
internal var _NRBITS: CInt       { CInt(8) }

@_alwaysEmitIntoClient
internal var _TYPEBITS: CInt     { CInt(8) }

@_alwaysEmitIntoClient
internal var _SIZEBITS: CInt     { CInt(14) }

@_alwaysEmitIntoClient
internal var _DIRBITS: CInt      { CInt(2) }

@_alwaysEmitIntoClient
internal var _NRMASK: CInt       { CInt((1 << _NRBITS)-1) }

@_alwaysEmitIntoClient
internal var _TYPEMASK: CInt     { CInt((1 << _TYPEBITS)-1) }

@_alwaysEmitIntoClient
internal var _SIZEMASK: CInt     { CInt((1 << _SIZEBITS)-1) }

@_alwaysEmitIntoClient
internal var _DIRMASK: CInt      { CInt((1 << _DIRBITS)-1) }

@_alwaysEmitIntoClient
internal var _NRSHIFT: CInt      { CInt(0) }

@_alwaysEmitIntoClient
internal var _TYPESHIFT: CInt    { CInt(_NRSHIFT+_NRBITS) }

@_alwaysEmitIntoClient
internal var _SIZESHIFT: CInt    { CInt(_TYPESHIFT+_TYPEBITS) }

@_alwaysEmitIntoClient
internal var _DIRSHIFT: CInt     { CInt(_SIZESHIFT+_SIZEBITS) }

#endif
