import Foundation
import Testing
import SystemPackage
@testable import Socket

@Suite("Socket Tests")
struct SocketTests {
    
    #if os(Linux)
    @Test("Unix Socket Communication")
    func testUnixSocket() async throws {
        let address = UnixSocketAddress(path: FilePath("/tmp/testsocket.sock"))
        print("Using path \(address.path.description)")
        let socketA = try await Socket(
            UnixProtocol.raw
        )
        print("Created socket A")
        let option: GenericSocketOption.ReuseAddress = true
        try socketA.fileDescriptor.setSocketOption(option)
        do { try socketA.fileDescriptor.bind(address) }
        catch { }
        defer { Task { await socketA.close() } }
        
        let socketB = try await Socket(
            UnixProtocol.raw
        )
        print("Created socket B")
        try socketB.fileDescriptor.setSocketOption(option)
        try socketB.fileDescriptor.bind(address)
        defer { Task { await socketB.close() } }
        
        let data = Data("Test \(UUID())".utf8)
        
        try await socketA.write(data)
        print("Socket A wrote data")
        let read = try await socketB.read(data.count)
        print("Socket B read data")
        #expect(data == read)
    }
    #endif
    
    @Test("IPv4 TCP Socket Communication")
    func testIPv4TCPSocket() async throws {
        let port = UInt16.random(in: 8080 ..< .max)
        print("Using port \(port)")
        let address = IPv4SocketAddress(address: .any, port: port)
        let data = Data("Test \(UUID())".utf8)
        let server = try await Socket(
            IPv4Protocol.tcp,
            bind: address
        )
        let newConnectionTask = Task {
            #expect(try server.fileDescriptor.address(IPv4SocketAddress.self) == address)
            print("Server: Created server socket \(server.fileDescriptor)")
            try await server.listen()
            
            print("Server: Waiting on incoming connection")
            let newConnection = try await server.accept()
            print("Server: Got incoming connection \(newConnection.fileDescriptor)")
            #expect(try newConnection.fileDescriptor.address(IPv4SocketAddress.self).address.rawValue == "127.0.0.1")
            let eventsTask = Task {
                var events = [Socket.Event]()
                for try await event in newConnection.event {
                    events.append(event)
                    print("Server Connection: \(event)")
                }
                return events
            }
            try await Task.sleep(nanoseconds: 10_000_000)
            let _ = try await newConnection.write(data)
            print("Server: Wrote outgoing data")
            return try await eventsTask.value
        }
        let serverEventsTask = Task {
            var events = [Socket.Event]()
            for try await event in server.event {
                events.append(event)
                print("Server: \(event)")
            }
            return events
        }
        
        let client = try await Socket(
            IPv4Protocol.tcp
        )
        let clientEventsTask = Task {
            var events = [Socket.Event]()
            for try await event in client.event {
                events.append(event)
                print("Client: \(event)")
            }
            return events
        }
        #expect(try client.fileDescriptor.address(IPv4SocketAddress.self).address == .any)
        print("Client: Created client socket \(client.fileDescriptor)")
        
        print("Client: Will connect to server")
        do { try await client.connect(to: address) }
        catch Errno.socketIsConnected { }
        print("Client: Connected to server")
        #expect(try client.fileDescriptor.address(IPv4SocketAddress.self).address.rawValue == "127.0.0.1")
        #expect(try client.fileDescriptor.peerAddress(IPv4SocketAddress.self).address.rawValue == "127.0.0.1")
        let read = try await client.read(data.count)
        print("Client: Read incoming data")
        #expect(data == read)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        await client.close()
        let clientEvents = try await clientEventsTask.value
        #expect(clientEvents.count == 4)
        #expect("\(clientEvents)" == "[Socket.Socket.Event.write, Socket.Socket.Event.read, Socket.Socket.Event.didRead(41), Socket.Socket.Event.close]")
        await server.close()
        let serverEvents = try await serverEventsTask.value
        #expect(serverEvents.count == 2)
        #expect("\(serverEvents)" == "[Socket.Socket.Event.connection, Socket.Socket.Event.close]")
        let newConnectionEvents = try await newConnectionTask.value
        #expect(newConnectionEvents.count == 5)
        #expect("\(newConnectionEvents)" == "[Socket.Socket.Event.write, Socket.Socket.Event.didWrite(41), Socket.Socket.Event.write, Socket.Socket.Event.read, Socket.Socket.Event.close]")
    }
    
    @Test("IPv4 UDP Socket Communication")
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
            print("Server: Created server socket \(server.fileDescriptor)")
            
            do {
                print("Server: Waiting to receive incoming message")
                let (read, clientAddress) = try await server.receiveMessage(data.count, fromAddressOf: type(of: address))
                print("Server: Received incoming message")
                #expect(data == read)
                
                print("Server: Waiting to send outgoing message")
                try await server.sendMessage(data, to: clientAddress)
                print("Server: Sent outgoing message")
            } catch {
                print("Server:", error)
                Issue.record("Server error: \(error)")
            }
        }
        
        let client = try await Socket(
            IPv4Protocol.udp
        )
        defer { Task { await client.close() } }
        print("Client: Created client socket \(client.fileDescriptor)")
        
        print("Client: Waiting to send outgoing message")
        try await client.sendMessage(data, to: address)
        print("Client: Sent outgoing message")
        
        print("Client: Waiting to receive incoming message")
        let (read, _) = try await client.receiveMessage(data.count, fromAddressOf: type(of: address))
        print("Client: Received incoming message")
        #expect(data == read)
    }
    
    @Test("Network Interface IPv4 Enumeration")
    func testNetworkInterfaceIPv4() throws {
        let interfaces = try NetworkInterface<IPv4SocketAddress>.interfaces
        if !isRunningInCI {
            #expect(!interfaces.isEmpty)
        }
        for interface in interfaces {
            print("\(interface.id.index). \(interface.id.name)")
            print("\(interface.address.address) \(interface.address.port)")
            if let netmask = interface.netmask {
                print("\(netmask.address) \(netmask.port)")
            }
        }
    }
    
    @Test("Network Interface IPv6 Enumeration")
    func testNetworkInterfaceIPv6() throws {
        let interfaces = try NetworkInterface<IPv6SocketAddress>.interfaces
        if !isRunningInCI {
            #expect(!interfaces.isEmpty)
        }
        for interface in interfaces {
            print("\(interface.id.index). \(interface.id.name)")
            print("\(interface.address.address) \(interface.address.port)")
            if let netmask = interface.netmask {
                print("\(netmask.address) \(netmask.port)")
            }
        }
    }
    
    #if canImport(Darwin) || os(Linux)
    @Test("Network Interface Link Layer Enumeration")
    func testNetworkInterfaceLinkLayer() throws {
        let interfaces = try NetworkInterface<LinkLayerSocketAddress>.interfaces
        for interface in interfaces {
            print("\(interface.id.index). \(interface.id.name)")
            print(interface.address.address)
            assert(interface.id.index == numericCast(interface.address.index))
        }
    }
    #endif
    
    @Test("IPv4 Loopback Address Byte Order Fix", .tags(.bugfix))
    func testIPv4LoopbackAddress() async throws {
        // Test the loopback address byte order issue from GitHub issue #18
        let loopback = IPv4Address.loopback
        #expect(loopback.rawValue == "127.0.0.1", "IPv4Address.loopback should return '127.0.0.1', not '1.0.0.127'")
        
        // Test that loopback is equivalent to manually constructed 127.0.0.1
        let manualLoopback = IPv4Address(127, 0, 0, 1)
        #expect(loopback == manualLoopback, "IPv4Address.loopback should equal manually constructed IPv4Address(127, 0, 0, 1)")
        
        // Test that loopback is equivalent to string-constructed address
        let stringLoopback = IPv4Address(rawValue: "127.0.0.1")!
        #expect(loopback == stringLoopback, "IPv4Address.loopback should equal string-constructed address")
        
        // Test that we can actually bind to loopback for TCP
        // This should not throw "Can't assign requested address" error
        let tcpAddress = IPv4SocketAddress(address: .loopback, port: 0)
        let tcpSocket = try await Socket(IPv4Protocol.tcp, bind: tcpAddress)
        defer { Task { await tcpSocket.close() } }
        
        // Test that we can also bind to loopback for UDP
        let udpAddress = IPv4SocketAddress(address: .loopback, port: 0)
        let udpSocket = try await Socket(IPv4Protocol.udp, bind: udpAddress)
        defer { Task { await udpSocket.close() } }
        
        // Verify the bound addresses are actually loopback
        let boundTcpAddress = try tcpSocket.fileDescriptor.address(IPv4SocketAddress.self)
        #expect(boundTcpAddress.address.rawValue == "127.0.0.1", "Bound TCP socket should be on loopback address")
        
        let boundUdpAddress = try udpSocket.fileDescriptor.address(IPv4SocketAddress.self)
        #expect(boundUdpAddress.address.rawValue == "127.0.0.1", "Bound UDP socket should be on loopback address")
    }
}

var isRunningInCI: Bool {
    let environmentVariables = [
        "GITHUB_ACTIONS",
        "TRAVIS",
        "CIRCLECI",
        "GITLAB_CI"
    ]
    for variable in environmentVariables {
        guard ProcessInfo.processInfo.environment[variable] == nil else {
            return true
        }
    }
    return false
}

extension Tag {
    @Tag static var bugfix: Self
}
