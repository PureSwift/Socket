import Foundation
import Testing
import SystemPackage
@testable import Socket

#if ENABLE_MOCKING
@Suite("Mocking Tests")
struct MockingTests {

    @Test("Syscalls are traced while mocking")
    func trace() throws {
        MockingDriver.withMockingEnabled { driver in
            let socket = SocketDescriptor(rawValue: 3)
            _ = socket._close()
            let entry = driver.trace.dequeue()
            #expect(entry?.name == "close")
            #expect(entry?.arguments == [AnyHashable(CInt(3))])
            #expect(driver.trace.isEmpty)
        }
    }

    @Test("Forced errno is thrown instead of performing the syscall")
    func forceErrno() throws {
        MockingDriver.withMockingEnabled { driver in
            driver.forceErrno = .always(errno: EBADF)
            let socket = SocketDescriptor(rawValue: 3)
            #expect(throws: Errno.badFileDescriptor) { try socket._close().get() }
        }
    }

    @Test("Counted errno applies to a fixed number of calls")
    func countedErrno() throws {
        MockingDriver.withMockingEnabled { driver in
            driver.forceErrno = .counted(errno: EBADF, count: 1)
            let socket = SocketDescriptor(rawValue: 3)
            #expect(throws: Errno.badFileDescriptor) { try socket._close().get() }
            #expect(throws: Never.self) { try socket._close().get() }
            #expect(driver.forceErrno == .none)
        }
    }

    @Test("Mocking is disabled outside the driver scope")
    func scoped() throws {
        #expect(contextualMockingEnabled == false)
        MockingDriver.withMockingEnabled { _ in
            #expect(contextualMockingEnabled)
        }
        #expect(contextualMockingEnabled == false)
    }
}
#endif
