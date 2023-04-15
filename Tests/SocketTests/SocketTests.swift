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
            XCTAssertEqual(try server.fileDescriptor.address(IPv4SocketAddress.self), address)
            defer { Task { await server.close() } }
            NSLog("Server: Created server socket \(server.fileDescriptor)")
            try server.fileDescriptor.listen(backlog: 10)
            
            NSLog("Server: Waiting on incoming connection")
            do {
                let newConnection = try await server.accept()
                NSLog("Server: Got incoming connection \(newConnection.fileDescriptor)")
                XCTAssertEqual(try newConnection.fileDescriptor.address(IPv4SocketAddress.self).address.rawValue, "127.0.0.1")
                try await Task.sleep(nanoseconds: 1_000_000_000)
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
        XCTAssertEqual(try client.fileDescriptor.address(IPv4SocketAddress.self).address, .any)
        defer { Task { await client.close() } }
        NSLog("Client: Created client socket \(client.fileDescriptor)")
        
        NSLog("Client: Will connect to server")
        do { try await client.connect(to: address) }
        catch Errno.socketIsConnected { }
        NSLog("Client: Connected to server")
        XCTAssertEqual(try client.fileDescriptor.address(IPv4SocketAddress.self).address.rawValue, "127.0.0.1")
        XCTAssertEqual(try client.fileDescriptor.peerAddress(IPv4SocketAddress.self).address.rawValue, "127.0.0.1")
        let read = try await client.read(data.count)
        NSLog("Client: Read incoming data")
        XCTAssertEqual(data, read)
    }
    
    func testIPv4UDPSocket() async throws {
        let port = UInt16.random(in: 8080 ..< .max)
        print("Using port \(port)")
        let address = IPv4SocketAddress(
            address: .any,
            port: port
        )
        let data = Data("Test \(UUID())".utf8)
        
        Task {
            let server = try await Socket(
                IPv4Protocol.udp,
                bind: address
            )
            defer { Task { await server.close() } }
            NSLog("Server: Created server socket \(server.fileDescriptor)")
            
            do {
                NSLog("Server: Waiting to receive incoming message")
                let (read, clientAddress) = try await server.receiveMessage(data.count, fromAddressOf: type(of: address))
                NSLog("Server: Received incoming message")
                XCTAssertEqual(data, read)
                
                NSLog("Server: Waiting to send outgoing message")
                try await server.sendMessage(data, to: clientAddress)
                NSLog("Server: Sent outgoing message")
            } catch {
                print("Server:", error)
                XCTFail("\(error)")
            }
        }
        
        let client = try await Socket(
            IPv4Protocol.udp
        )
        defer { Task { await client.close() } }
        NSLog("Client: Created client socket \(client.fileDescriptor)")
        
        NSLog("Client: Waiting to send outgoing message")
        try await client.sendMessage(data, to: address)
        NSLog("Client: Sent outgoing message")
        
        NSLog("Client: Waiting to receive incoming message")
        let (read, _) = try await client.receiveMessage(data.count, fromAddressOf: type(of: address))
        NSLog("Client: Received incoming message")
        XCTAssertEqual(data, read)
    }
    
    func testNetworkInterfaceIPv4() throws {
        let interfaces = try NetworkInterface<IPv4SocketAddress>.interfaces
        XCTAssert(interfaces.isEmpty == false)
        for interface in interfaces {
            print("\(interface.id.index). \(interface.id.name)")
            print("\(interface.address.address) \(interface.address.port)")
            if let netmask = interface.netmask {
                print("\(netmask.address) \(netmask.port)")
            }
        }
    }
    
    func testNetworkInterfaceIPv6() throws {
        let interfaces = try NetworkInterface<IPv6SocketAddress>.interfaces
        XCTAssert(interfaces.isEmpty == false)
        for interface in interfaces {
            print("\(interface.id.index). \(interface.id.name)")
            print("\(interface.address.address) \(interface.address.port)")
            if let netmask = interface.netmask {
                print("\(netmask.address) \(netmask.port)")
            }
        }
    }
    
    func testNetworkInterfaceLinkLayer() throws {
        let interfaces = try NetworkInterface<LinkLayerSocketAddress>.interfaces
        XCTAssert(interfaces.isEmpty == false)
        for interface in interfaces {
            print("\(interface.id.index). \(interface.id.name)")
            print(interface.address.address)
            assert(interface.id.index == numericCast(interface.address.index))
        }
    }
}
