import Foundation
import XCTest
import SystemPackage
@testable import Socket

final class SocketTests: XCTestCase {
    
    func _testUnixSocket() async throws {
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
    
    @available(macOS 12, *)
    func testIPv4Socket() async throws {
        let address = IPv4SocketAddress(address: .init(rawValue: "127.0.0.1")!, port: 8081)
        let data = Data("Test \(UUID())".utf8)
        
        let server = try Socket(
            fileDescriptor: .socket(IPv4Protocol.tcp)
        )
        defer { server.close() }
        try server.fileDescriptor.bind(address)
        NSLog("Server: Created server socket")
        try server.fileDescriptor.listen(backlog: 10)
        
        Task {
            do {
                let newConnection = try await server.fileDescriptor.accept()
                defer { try? newConnection.close() }
                NSLog("Server: Got incoming connection")
                let _ = try await newConnection.write(data)
                NSLog("Server: Wrote outgoing data")
            } catch {
                print("Server:", error)
                XCTFail("\(error)")
            }
        }
        
        let client = try Socket(
            fileDescriptor: .socket(IPv4Protocol.tcp)
        )
        defer { client.close() }
        
        try await client.fileDescriptor.connect(to: address, sleep: 10_000_000)
        NSLog("Client: Connected to server")
        let read = try await client.read(data.count)
        NSLog("Client: Read incoming data")
        XCTAssertEqual(data, read)
    }
}
