// Results in errno if i == -1
private func valueOrErrno<I: FixedWidthInteger>(
  _ i: I
) -> Result<I, Errno> {
  i == -1 ? .failure(Errno.current) : .success(i)
}

private func nothingOrErrno<I: FixedWidthInteger>(
  _ i: I
) -> Result<(), Errno> {
  valueOrErrno(i).map { _ in () }
}

internal func valueOrErrno<I: FixedWidthInteger>(
  retryOnInterrupt: Bool, _ f: () -> I
) -> Result<I, Errno> {
  repeat {
    switch valueOrErrno(f()) {
    case .success(let r): return .success(r)
    case .failure(let err):
      guard retryOnInterrupt && err == .interrupted else { return .failure(err) }
      break
    }
  } while true
}

internal func nothingOrErrno<I: FixedWidthInteger>(
  retryOnInterrupt: Bool, _ f: () -> I
) -> Result<(), Errno> {
  valueOrErrno(retryOnInterrupt: retryOnInterrupt, f).map { _ in () }
}

// Run a precondition for debug client builds
internal func _debugPrecondition(
  _ condition: @autoclosure () -> Bool,
  _ message: StaticString = StaticString(),
  file: StaticString = #file, line: UInt = #line
) {
  // Only check in debug mode.
  if _slowPath(_isDebugAssertConfiguration()) {
    precondition(
      condition(), String(describing: message), file: file, line: line)
  }
}

extension OpaquePointer {
  internal var _isNULL: Bool {
    OpaquePointer(bitPattern: Int(bitPattern: self)) == nil
  }
}

extension Sequence {
  // Tries to recast contiguous pointer if available, otherwise allocates memory.
  internal func _withRawBufferPointer<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R
  ) rethrows -> R {
    guard let result = try self.withContiguousStorageIfAvailable({
      try body(UnsafeRawBufferPointer($0))
    }) else {
      return try Array(self).withUnsafeBytes(body)
    }
    return result
  }
}

extension MutableCollection {
  // Tries to recast contiguous pointer if available, otherwise allocates memory.
  internal mutating func _withMutableRawBufferPointer<R>(
    _ body: (UnsafeMutableRawBufferPointer) throws -> R
  ) rethrows -> R {
    guard let result = try self.withContiguousMutableStorageIfAvailable({
      try body(UnsafeMutableRawBufferPointer($0))
    }) else {
        fatalError()
    }
    return result
  }
}

extension OptionSet {
  // Helper method for building up a comma-separated list of options
  //
  // Taking an array of descriptions reduces code size vs
  // a series of calls due to avoiding register copies. Make sure
  // to pass an array literal and not an array built up from a series of
  // append calls, else that will massively bloat code size. This takes
  // StaticStrings because otherwise we get a warning about getting evicted
  // from the shared cache.
  @inline(never)
  internal func _buildDescription(
    _ descriptions: [(Element, StaticString)]
  ) -> String {
    var copy = self
    var result = "["

    for (option, name) in descriptions {
      if _slowPath(copy.contains(option)) {
        result += name.description
        copy.remove(option)
        if !copy.isEmpty { result += ", " }
      }
    }

    if _slowPath(!copy.isEmpty) {
      result += "\(Self.self)(rawValue: \(copy.rawValue))"
    }
    result += "]"
    return result
  }
}

internal extension Sequence {
    
    func _buildDescription() -> String {
        var string = "["
        for element in self {
            if _slowPath(string.count == 1) {
                string += "\(element)"
            } else {
                string += ", \(element)"
            }
        }
        string += "]"
        return string
    }
}

internal func _dropCommonPrefix<C: Collection>(
  _ lhs: C, _ rhs: C
) -> (C.SubSequence, C.SubSequence)
where C.Element: Equatable {
  var (lhs, rhs) = (lhs[...], rhs[...])
  while lhs.first != nil && lhs.first == rhs.first {
    lhs.removeFirst()
    rhs.removeFirst()
  }
  return (lhs, rhs)
}

extension MutableCollection where Element: Equatable {
  mutating func _replaceAll(_ e: Element, with new: Element) {
    for idx in self.indices {
      if self[idx] == e { self[idx] = new }
    }
  }
}

internal extension Bool {
    
    @usableFromInline
    init(_ cInt: CInt) {
        self = cInt != 0
    }
    
    @usableFromInline
    var cInt: CInt {
        self ? 1 : 0
    }
}

/// Pauses the current task if the operation throws ``Errno/wouldBlock`` or other async I/O errors.
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
@usableFromInline
func retry<T>(
    sleep nanoseconds: UInt64,
    _ body: () -> Result<T, Errno>
) async throws -> Result<T, Errno> {
    repeat {
        try Task.checkCancellation()
        switch body() {
        case let .success(result):
            return .success(result)
        case let .failure(error):
            guard error.isBlocking else {
                return .failure(error)
            }
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    } while true
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
@usableFromInline
func retry<T>(
    sleep: UInt64, // ns
    timeout: UInt, // ms
    condition: (T) -> (Bool) = { _ in return true },
    _ body: () -> Result<T, Errno>
) async throws -> T {
    assert(timeout > 0, "\(#function) Must specify a timeout")
    // convert ms to ns
    var timeRemaining = UInt64(timeout) * 1_000_000
    repeat {
        // immediately get poll results
        switch body() {
        case let .success(events):
            // sleep if no events
            guard condition(events) == false else {
                return events
            }
        case let .failure(error):
            // sleep if blocking error is thrown
            guard error.isBlocking else {
                throw error
            }
        }
        // check for cancellation
        try Task.checkCancellation()
        // check if we have time remaining
        guard timeRemaining > sleep else {
            throw Errno.timedOut
        }
        // check clock?
        timeRemaining -= sleep
        try await Task.sleep(nanoseconds: sleep) // checks for cancelation
    } while true
}

internal extension Errno {
    
    var isBlocking: Bool {
        switch self {
        case .wouldBlock,
            .nowInProgress,
            .alreadyInProcess,
            .resourceTemporarilyUnavailable:
            return true
        default:
            return false
        }
    }
}
