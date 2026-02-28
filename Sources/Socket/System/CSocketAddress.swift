import SystemPackage

internal protocol CSocketAddress {
    
    static var family: SocketAddressFamily { get }
    
    init()
}

internal extension CSocketAddress {
    
    func withUnsafePointer<Result>(
        _ body: (UnsafePointer<CInterop.SocketAddress>, CInterop.SocketLength) throws -> Result
        ) rethrows -> Result {
        return try Swift.withUnsafeBytes(of: self) {
            return try body($0.baseAddress!.assumingMemoryBound(to:  CInterop.SocketAddress.self), CInterop.SocketLength(MemoryLayout<Self>.size))
        }
    }
    
    mutating func withUnsafeMutablePointer<Result>(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, CInterop.SocketLength) throws -> Result
        ) rethrows -> Result {
            return try Swift.withUnsafeMutableBytes(of: &self) {
                return try body($0.baseAddress!.assumingMemoryBound(to:  CInterop.SocketAddress.self), CInterop.SocketLength(MemoryLayout<Self>.size))
        }
    }
}
