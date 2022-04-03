import Foundation
import XCTest
import SystemPackage
@testable import Socket

final class SocketTests: XCTestCase {
    
    func testUnixSocket() async throws {
        let address = UnixSocketAddress(path: "/tmp/socket1")
        let socketA = try Socket(
            fileDescriptor: .socket(UnixProtocol.raw, bind: address)
        )
        defer { socketA.close() }
        
        let socketB = try Socket(
            fileDescriptor: .socket(UnixProtocol.raw, bind: address)
        )
        defer { socketB.close() }
        
        let data = Data("Test \(UUID())".utf8)
        
        try await socketA.write(data)
        let read = try await socketB.read(data.count)
        XCTAssertEqual(data, read)
    }
    
    func testIPv4Socket() async throws {
        let address = IPv4SocketAddress(address: .loopback, port: 8081)
        
        let socketA = try Socket(
            fileDescriptor: .socket(IPv4Protocol.tcp)
        )
        defer { socketA.close() }
        
        let socketB = try Socket(
            fileDescriptor: .socket(IPv4Protocol.tcp)
        )
        defer { socketB.close() }
        
        let data = Data("Test \(UUID())".utf8)
        
        try await socketA.write(data)
        let read = try await socketB.read(data.count)
        XCTAssertEqual(data, read)
    }
}
