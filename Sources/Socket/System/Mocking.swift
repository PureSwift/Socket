//
//  Mocking.swift
//  Socket
//

#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import ucrt
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(Android)
import Android
#endif

// Syscall mocks, modeled after the mechanism in swift-system.

/// A single recorded syscall invocation.
internal struct Trace {

    internal struct Entry: Hashable {

        internal var name: String

        internal var arguments: [AnyHashable]

        internal init(name: String, _ arguments: [AnyHashable]) {
            self.name = name
            self.arguments = arguments
        }
    }

    private var entries: [Entry] = []

    private var firstUnchecked = 0

    internal mutating func add(_ entry: Entry) {
        entries.append(entry)
    }

    internal var isEmpty: Bool { firstUnchecked >= entries.count }

    /// The next unchecked entry, advancing the cursor past it.
    internal mutating func dequeue() -> Entry? {
        guard isEmpty == false else { return nil }
        defer { firstUnchecked += 1 }
        return entries[firstUnchecked]
    }

    internal var unchecked: ArraySlice<Entry> { entries[firstUnchecked...] }

    internal var all: [Entry] { entries }
}

/// An error to force upon the next syscall(s) instead of performing them.
internal enum ForceErrno: Equatable {

    case none

    case always(errno: CInt)

    case counted(errno: CInt, count: Int)
}

/// Receives the syscall trace and supplies forced errors while mocking is enabled.
internal final class MockingDriver {

    internal var trace = Trace()

    internal var forceErrno = ForceErrno.none

    internal init() { }
}

#if ENABLE_MOCKING
#if os(Windows)
private let key: _tls_index = {
    let raw = FlsAlloc(nil)
    guard raw != FLS_OUT_OF_INDEXES else { fatalError("Unable to create thread local storage") }
    return raw
}()

private func getDriver() -> MockingDriver? {
    guard let raw = FlsGetValue(key) else { return nil }
    return Unmanaged.fromOpaque(raw).takeUnretainedValue()
}

private func setDriver(_ driver: MockingDriver?) {
    let raw = driver.map { Unmanaged.passUnretained($0).toOpaque() }
    FlsSetValue(key, raw)
}
#elseif canImport(WASILibc)
// WASI is single threaded, a global is equivalent to thread local storage.
nonisolated(unsafe) private var driver: MockingDriver?

private func getDriver() -> MockingDriver? { driver }

private func setDriver(_ newValue: MockingDriver?) { driver = newValue }
#else
private let key: pthread_key_t = {
    var raw = pthread_key_t()
    guard pthread_key_create(&raw, nil) == 0 else {
        fatalError("Unable to create thread local storage")
    }
    return raw
}()

private func getDriver() -> MockingDriver? {
    guard let raw = pthread_getspecific(key) else { return nil }
    return Unmanaged.fromOpaque(raw).takeUnretainedValue()
}

private func setDriver(_ driver: MockingDriver?) {
    let raw = driver.map { Unmanaged.passUnretained($0).toOpaque() }
    pthread_setspecific(key, raw)
}
#endif

/// The driver for the current thread, if mocking is enabled for it.
internal var currentMockingDriver: MockingDriver? { getDriver() }

internal var contextualMockingEnabled: Bool { getDriver() != nil }

extension MockingDriver {

    /// Enables mocking for the duration of `body`, which receives the driver
    /// recording every syscall made on the current thread.
    internal static func withMockingEnabled<T>(
        _ body: (MockingDriver) throws -> T
    ) rethrows -> T {
        let driver = MockingDriver()
        let previous = getDriver()
        setDriver(driver)
        defer { setDriver(previous) }
        return try body(driver)
    }
}
#endif
