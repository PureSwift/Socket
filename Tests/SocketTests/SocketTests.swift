import Foundation
import Testing
import SystemPackage
import Logging
@testable import Socket

@Suite("Socket Tests")
struct SocketTests {
    
    static let logger = Logger(label: "logger") { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        // handler.logLevel = .debug
        return handler
    }
    
    #if os(Linux)
    @Test("Unix Socket Communication")
    func testUnixSocket() async throws {
        let address = UnixSocketAddress(path: FilePath("/tmp/testsocket.sock"))
        Self.logger.info("Using path \(address.path.description)")
        let socketA = try await Socket(
            UnixProtocol.raw
        )
        Self.logger.info("Created socket A")
        let option: GenericSocketOption.ReuseAddress = true
        try socketA.fileDescriptor.setSocketOption(option)
        do { try socketA.fileDescriptor.bind(address) }
        catch { }
        defer { Task { await socketA.close() } }
        
        let socketB = try await Socket(
            UnixProtocol.raw
        )
        Self.logger.info("Created socket B")
        try socketB.fileDescriptor.setSocketOption(option)
        try socketB.fileDescriptor.bind(address)
        defer { Task { await socketB.close() } }
        
        let data = Data("Test \(UUID())".utf8)
        
        try await socketA.write(data)
        Self.logger.info("Socket A wrote data")
        let read = try await socketB.read(data.count)
        Self.logger.info("Socket B read data")
        #expect(data == read)
    }
    #endif
    
    @Test("IPv4 TCP Socket Communication")
    func testIPv4TCPSocket() async throws {
        let port = UInt16.random(in: 8080 ..< .max)
        Self.logger.info("Using port \(port)")
        let address = IPv4SocketAddress(address: .any, port: port)
        let data = Data("Test \(UUID())".utf8)
        let server = try await Socket(
            IPv4Protocol.tcp,
            bind: address
        )
        let newConnectionTask = Task {
            #expect(try server.fileDescriptor.address(IPv4SocketAddress.self) == address)
            Self.logger.info("Server: Created server socket \(server.fileDescriptor)")
            try await server.listen()
            
            Self.logger.info("Server: Waiting on incoming connection")
            let newConnection = try await server.accept()
            Self.logger.info("Server: Got incoming connection \(newConnection.fileDescriptor)")
            #expect(try newConnection.fileDescriptor.address(IPv4SocketAddress.self).address.rawValue == "127.0.0.1")
            let eventsTask = Task {
                var events = [Socket.Event]()
                for try await event in newConnection.event {
                    events.append(event)
                    Self.logger.info("Server Connection: \(event)")
                }
                return events
            }
            try await Task.sleep(nanoseconds: 10_000_000)
            let _ = try await newConnection.write(data)
            Self.logger.info("Server: Wrote outgoing data")
            return try await eventsTask.value
        }
        let serverEventsTask = Task {
            var events = [Socket.Event]()
            for try await event in server.event {
                events.append(event)
                Self.logger.info("Server: \(event)")
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
                Self.logger.info("Client: \(event)")
            }
            return events
        }
        #expect(try client.fileDescriptor.address(IPv4SocketAddress.self).address == .any)
        Self.logger.info("Client: Created client socket \(client.fileDescriptor)")
        
        Self.logger.info("Client: Will connect to server")
        do { try await client.connect(to: address) }
        catch Errno.socketIsConnected { }
        Self.logger.info("Client: Connected to server")
        #expect(try client.fileDescriptor.address(IPv4SocketAddress.self).address.rawValue == "127.0.0.1")
        #expect(try client.fileDescriptor.peerAddress(IPv4SocketAddress.self).address.rawValue == "127.0.0.1")
        let read = try await client.read(data.count)
        Self.logger.info("Client: Read incoming data")
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
        Self.logger.info("Using port \(port)")
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
            Self.logger.info("Server: Created server socket \(server.fileDescriptor)")
            
            do {
                Self.logger.info("Server: Waiting to receive incoming message")
                let (read, clientAddress) = try await server.receiveMessage(data.count, fromAddressOf: type(of: address))
                Self.logger.info("Server: Received incoming message")
                #expect(data == read)
                
                Self.logger.info("Server: Waiting to send outgoing message")
                try await server.sendMessage(data, to: clientAddress)
                Self.logger.info("Server: Sent outgoing message")
            } catch {
                Self.logger.error("Server error: \(error)")
                Issue.record("Server error: \(error)")
            }
        }
        
        let client = try await Socket(
            IPv4Protocol.udp
        )
        defer { Task { await client.close() } }
        Self.logger.info("Client: Created client socket \(client.fileDescriptor)")
        
        Self.logger.info("Client: Waiting to send outgoing message")
        try await client.sendMessage(data, to: address)
        Self.logger.info("Client: Sent outgoing message")
        
        Self.logger.info("Client: Waiting to receive incoming message")
        let (read, _) = try await client.receiveMessage(data.count, fromAddressOf: type(of: address))
        Self.logger.info("Client: Received incoming message")
        #expect(data == read)
    }
    
    @Test("Network Interface IPv4 Enumeration")
    func testNetworkInterfaceIPv4() throws {
        let interfaces = try NetworkInterface<IPv4SocketAddress>.interfaces
        if !isRunningInCI {
            #expect(!interfaces.isEmpty)
        }
        for interface in interfaces {
            Self.logger.info("\(interface.id.index). \(interface.id.name)")
            Self.logger.info("\(interface.address.address) \(interface.address.port)")
            if let netmask = interface.netmask {
                Self.logger.info("\(netmask.address) \(netmask.port)")
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
            Self.logger.info("\(interface.id.index). \(interface.id.name)")
            Self.logger.info("\(interface.address.address) \(interface.address.port)")
            if let netmask = interface.netmask {
                Self.logger.info("\(netmask.address) \(netmask.port)")
            }
        }
    }
    
    #if canImport(Darwin) || os(Linux)
    @Test("Network Interface Link Layer Enumeration")
    func testNetworkInterfaceLinkLayer() throws {
        let interfaces = try NetworkInterface<LinkLayerSocketAddress>.interfaces
        for interface in interfaces {
            Self.logger.info("\(interface.id.index). \(interface.id.name)")
            Self.logger.info("\(interface.address.address)")
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
  
    @Test
    func tcpNoDelay() async throws {
        // Create a TCP socket
        let socket = try await Socket(IPv4Protocol.tcp)
        defer { Task { await socket.close() } }
        
        // Test setting TCP_NODELAY option
        let nodelay = TCPSocketOption.NoDelay(true)
        try socket.setOption(nodelay)
        
        // Test getting TCP_NODELAY option
        let retrievedOption = try socket[TCPSocketOption.NoDelay.self]
        #expect(retrievedOption.boolValue == true)
        
        // Test disabling TCP_NODELAY
        let disableNodelay = TCPSocketOption.NoDelay(false)
        try socket.setOption(disableNodelay)
        
        let retrievedDisabled = try socket[TCPSocketOption.NoDelay.self]
        #expect(retrievedDisabled.boolValue == false)
        
        // Test with boolean literal
        let literalOption: TCPSocketOption.NoDelay = true
        try socket.setOption(literalOption)
        
        let retrievedLiteral = try socket[TCPSocketOption.NoDelay.self]
        #expect(retrievedLiteral.boolValue == true)
    }
    
    @Test
    func tcpNoDelayBehavior() async throws {
        // This test verifies that TCP_NODELAY option works by testing with a connected socket pair
        let port = UInt16.random(in: 8080 ..< .max)
        print("Testing TCP_NODELAY behavior on port \(port)")
        let address = IPv4SocketAddress(address: .any, port: port)
        
        // Create server
        let server = try await Socket(IPv4Protocol.tcp, bind: address)
        defer { Task { await server.close() } }
        
        // Start server listening
        try await server.listen()
        
        // Connect client and verify TCP_NODELAY can be set
        let client = try await Socket(IPv4Protocol.tcp)
        defer { Task { await client.close() } }
        
        // Test that we can set TCP_NODELAY before connecting
        try client.setOption(TCPSocketOption.NoDelay(true))
        let nodeDelayBeforeConnect = try client[TCPSocketOption.NoDelay.self]
        #expect(nodeDelayBeforeConnect.boolValue == true)
        
        // Connect to server
        do { try await client.connect(to: address) }
        catch Errno.socketIsConnected { }
        
        // Accept connection on server side
        let serverConnection = try await server.accept()
        defer { Task { await serverConnection.close() } }
        
        // Verify TCP_NODELAY is still set after connection
        let nodeDelayAfterConnect = try client[TCPSocketOption.NoDelay.self]
        #expect(nodeDelayAfterConnect.boolValue == true)
        
        // Test setting TCP_NODELAY on the server's accepted connection
        try serverConnection.setOption(TCPSocketOption.NoDelay(false))
        let serverNodeDelay = try serverConnection[TCPSocketOption.NoDelay.self]
        #expect(serverNodeDelay.boolValue == false)
        
        // Demonstrate that small writes work with TCP_NODELAY
        // (The actual latency difference is hard to measure reliably on localhost)
        let testData = Data("Hello".utf8)
        try await client.write(testData)
        
        let receivedData = try await serverConnection.read(testData.count)
        #expect(testData == receivedData)
        
        print("Successfully tested TCP_NODELAY option setting and data transmission")
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
