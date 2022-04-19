import Foundation
import XCTest
import SystemPackage
@testable import Socket

final class SocketTests: XCTestCase {
    
    func _testUnixSocket() async throws {
        let address = UnixSocketAddress(path: "/tmp/socket1")
        let socketA = try await Socket(
            fileDescriptor: .socket(UnixProtocol.raw, bind: address)
        )
        defer { socketA.close() }
        
        let socketB = try await Socket(
            fileDescriptor: .socket(UnixProtocol.raw, bind: address)
        )
        defer { socketB.close() }
        
        let data = Data("Test \(UUID())".utf8)
        
        try await socketA.write(data)
        let read = try await socketB.read(data.count)
        XCTAssertEqual(data, read)
    }
    
    func testIPv4Socket() async throws {
        let address = IPv4SocketAddress(address: .any, port: 8888)
        let data = Data("Test \(UUID())".utf8)
        
        let server = try await Socket(
            fileDescriptor: .socket(IPv4Protocol.tcp, bind: address)
        )
        defer { server.close() }
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
        
        NSLog("Client: Created client socket")
        let client = try await Socket(
            fileDescriptor: .socket(IPv4Protocol.tcp)
        )
        defer { client.close() }
        
        NSLog("Client: Will connect to server")
        try await client.fileDescriptor.connect(to: address, sleep: 100_000_000)
        NSLog("Client: Connected to server")
        let read = try await client.read(data.count)
        NSLog("Client: Read incoming data")
        XCTAssertEqual(data, read)
    }
}
