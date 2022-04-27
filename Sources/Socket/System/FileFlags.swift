//
//  Flags.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

import SystemPackage

public extension FileDescriptor {
    
    /// Options that specify behavior for file descriptors.
    @frozen
    struct Flags: OptionSet, Hashable, Codable {
        
        /// The raw C options.
        @_alwaysEmitIntoClient
        public var rawValue: CInt

        /// Create a strongly-typed options value from raw C options.
        @_alwaysEmitIntoClient
        public init(rawValue: CInt) { self.rawValue = rawValue }

        @_alwaysEmitIntoClient
        private init(_ raw: CInt) { self.init(rawValue: raw) }
        
        /// Indicates that executing a program closes the file.
        ///
        /// Normally, file descriptors remain open
        /// across calls to the `exec(2)` family of functions.
        /// If you specify this option,
        /// the file descriptor is closed when replacing this process
        /// with another process.
        ///
        /// The state of the file
        /// descriptor flags can be inspected using `F_GETFD`,
        /// as described in the `fcntl(2)` man page.
        ///
        /// The corresponding C constant is `FD_CLOEXEC`.
        @_alwaysEmitIntoClient
        public static var closeOnExec: Flags { Flags(_FD_CLOEXEC) }
      }
}

extension FileDescriptor.Flags
  : CustomStringConvertible, CustomDebugStringConvertible
{
  /// A textual representation of the access mode.
  @inline(never)
  public var description: String {
    switch self {
    case .closeOnExec: return "closeOnExec"
    default: return "\(Self.self)(rawValue: \(self.rawValue))"
    }
  }

  /// A textual representation of the access mode, suitable for debugging
  public var debugDescription: String { self.description }
}
