//
//  SocketHelpers.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

extension SocketDescriptor {
    
    /// Runs a closure and then closes the file descriptor, even if an error occurs.
    ///
    /// - Parameter body: The closure to run.
    ///   If the closure throws an error,
    ///   this method closes the file descriptor before it rethrows that error.
    ///
    /// - Returns: The value returned by the closure.
    ///
    /// If `body` throws an error
    /// or an error occurs while closing the file descriptor,
    /// this method rethrows that error.
    public func closeAfter<R>(_ body: () throws -> R) throws -> R {
      // No underscore helper, since the closure's throw isn't necessarily typed.
      let result: R
      do {
        result = try body()
      } catch {
        _ = try? self.close() // Squash close error and throw closure's
        throw error
      }
      try self.close()
      return result
    }
    
    /// Runs a closure and then closes the file descriptor if an error occurs.
    ///
    /// - Parameter body: The closure to run.
    ///   If the closure throws an error,
    ///   this method closes the file descriptor before it rethrows that error.
    ///
    /// - Returns: The value returned by the closure.
    ///
    /// If `body` throws an error
    /// this method rethrows that error.
    @_alwaysEmitIntoClient
    public func closeIfThrows<R>(_ body: () throws -> R) throws -> R {
        do {
          return try body()
        } catch {
          _ = self._close() // Squash close error and throw closure's
          throw error
        }
    }
    
    #if swift(>=5.5)
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func closeIfThrows<R>(_ body: () async throws -> R) async throws -> R {
        do {
          return try await body()
        } catch {
          _ = self._close() // Squash close error and throw closure's
          throw error
        }
    }
    #endif
    
    @usableFromInline
    internal func _closeIfThrows<R>(_ body: () -> Result<R, Errno>) -> Result<R, Errno> {
        return body().mapError {
            // close if error is thrown
            let _ = _close()
            return $0
        }
    }
}

internal extension Result where Success == SocketDescriptor, Failure == Errno {
    
    @usableFromInline
    func _closeIfThrows<R>(_ body: (SocketDescriptor) -> Result<R, Errno>) -> Result<R, Errno> {
        return flatMap { fileDescriptor in
            fileDescriptor._closeIfThrows {
                body(fileDescriptor)
            }
        }
    }
}
