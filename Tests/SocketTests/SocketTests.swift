import Foundation
import XCTest
import SystemPackage
@testable import Socket

final class SocketTests: XCTestCase {
    
    #if os(Linux)
    func _testUnixSocket() async throws {
        let address = UnixSocketAddress(path: FilePath("/tmp/testsocket.sock"))
        NSLog("Using path \(address.path.description)")
        let socketA = try await Socket(
            UnixProtocol.raw
        )
        NSLog("Created socket A")
        let option: GenericSocketOption.ReuseAddress = true
        try socketA.fileDescriptor.setSocketOption(option)
        do { try socketA.fileDescriptor.bind(address) }
        catch { }
        defer { Task { await socketA.close() } }
        
        let socketB = try await Socket(
            UnixProtocol.raw
        )
        NSLog("Created socket B")
        try socketB.fileDescriptor.setSocketOption(option)
        try socketB.fileDescriptor.bind(address)
        defer { Task { await socketB.close() } }
        
        let data = Data("Test \(UUID())".utf8)
        
        try await socketA.write(data)
        NSLog("Socket A wrote data")
        let read = try await socketB.read(data.count)
        NSLog("Socket B read data")
        XCTAssertEqual(data, read)
    }
    #endif
    
    func testIPv4TCPSocket() async throws {
        let port = UInt16.random(in: 8080 ..< .max)
        print("Using port \(port)")
        let address = IPv4SocketAddress(address: .any, port: port)
        let data = Data("Test \(UUID())".utf8)
        
        Task {
            let server = try await Socket(
                IPv4Protocol.tcp,
                bind: address
            )
            defer { Task { await server.close() } }
            NSLog("Server: Created server socket \(server.fileDescriptor)")
            try server.fileDescriptor.listen(backlog: 10)
            
            NSLog("Server: Waiting on incoming connection")
            do {
                let newConnection = await Socket(
                    fileDescriptor: try await server.fileDescriptor.accept()
                )
                NSLog("Server: Got incoming connection \(newConnection.fileDescriptor)")
                let _ = try await newConnection.write(data)
                NSLog("Server: Wrote outgoing data")
            } catch {
                print("Server:", error)
                XCTFail("\(error)")
            }
        }
        
        let client = try await Socket(
            IPv4Protocol.tcp
        )
        defer { Task { await client.close() } }
        NSLog("Client: Created client socket \(client.fileDescriptor)")
        
        NSLog("Client: Will connect to server")
        do { try await client.fileDescriptor.connect(to: address, sleep: 100_000_000) }
        catch Errno.socketIsConnected { }
        NSLog("Client: Connected to server")
        let read = try await client.read(data.count)
        NSLog("Client: Read incoming data")
        XCTAssertEqual(data, read)
    }
    
    func testIPv4UDPSocket() async throws {
        let sourcePort = UInt16.random(in: 8080 ..< .max)
        let sourceAddress = IPv4SocketAddress(address: .any, port: sourcePort)
        
        let destinationPort = UInt16.random(in: 8080 ..< .max)
        let destinationAddress = IPv4SocketAddress(address: .any, port: destinationPort)
        
        let data = Data("Test \(UUID())".utf8)
        
        Task {
            let server = try await Socket(
                IPv4Protocol.udp,
                bind: destinationAddress
            )
            
            NSLog("Server: Created server socket \(server.fileDescriptor)")
            defer { Task { await server.close() } }
            
            NSLog("Server: Will connect to client")
            do { try await server.fileDescriptor.connect(to: sourceAddress, sleep: 100_000_000) }
            catch Errno.socketIsConnected { }
            
            do {
                let _ = try await server.sendMessage(data)
                NSLog("Server: Wrote outgoing data")
                
                let read = try await server.receiveMessage(data.count)
                NSLog("Server: Read incoming data")
                XCTAssertEqual(data, read)
            } catch {
                print("Server:", error)
                XCTFail("\(error)")
            }
        }
        
        let client = try await Socket(
            IPv4Protocol.udp,
            bind: sourceAddress
        )
        
        NSLog("Client: Created client socket \(client.fileDescriptor)")
        defer { Task { await client.close() } }
        
        NSLog("Client: Will connect to server")
        do { try await client.fileDescriptor.connect(to: destinationAddress, sleep: 100_000_000) }
        catch Errno.socketIsConnected { }
        
        let read = try await client.receiveMessage(data.count)
        NSLog("Client: Read incoming data")
        XCTAssertEqual(data, read)
        
        let _ = try await client.sendMessage(data)
        NSLog("Client: Wrote outgoing data")
    }
    
    func testNetworkInterface() throws {
        let interfaces = try NetworkInterface.interfaces
        XCTAssert(interfaces.isEmpty == false)
        for interface in interfaces {
            print("\(interface.id). \(interface.name)")
        }
    }
}
