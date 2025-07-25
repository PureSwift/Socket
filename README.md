# Socket

A modern Swift library for working with POSIX sockets using async/await.

## Overview

Socket is a low-level networking library that provides a Swift-native interface for socket programming. It leverages Swift's async/await concurrency model to offer non-blocking I/O operations without the complexity of callbacks or legacy technologies like CFSocket or GCD.

### Key Features

- ✅ **Pure Swift Concurrency** - Built exclusively with async/await
- ✅ **Cross-Platform** - Supports macOS, iOS, tvOS, watchOS, and Linux
- ✅ **Multiple Protocols** - TCP, UDP, Unix domain sockets, and raw sockets
- ✅ **IPv4 & IPv6** - Full support for both IP versions
- ✅ **Type-Safe** - Leverages Swift's type system for socket options and addresses
- ✅ **High Performance** - Minimal overhead with value types and efficient polling
- ✅ **Event Streams** - Monitor socket events with AsyncStream

## Installation

### Swift Package Manager

Add Socket to your `Package.swift` file:

```swift
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    dependencies: [
        .package(url: "https://github.com/PureSwift/Socket.git", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: ["Socket"]
        )
    ]
)
```

Then run:
```bash
swift package resolve
```

### Xcode

1. In Xcode, select **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/PureSwift/Socket`
3. Select the version you want to use
4. Add Socket to your target

## Quick Start

### TCP Client

```swift
import Socket

// Connect to a TCP server
let socket = try await Socket(IPv4Protocol.tcp)
let address = IPv4SocketAddress(address: .init(127, 0, 0, 1), port: 8080)
try await socket.connect(to: address)

// Send data
let message = "Hello, Server!".data(using: .utf8)!
try await socket.write(message)

// Receive response
let response = try await socket.read(1024)
print("Received: \(String(data: response, encoding: .utf8) ?? "")")

// Close the socket
await socket.close()
```

### TCP Server

```swift
import Socket

// Create a server socket
let address = IPv4SocketAddress(address: .any, port: 8080)
let server = try await Socket(IPv4Protocol.tcp, bind: address)
try await server.listen(backlog: 10)

print("Server listening on port 8080")

// Accept connections
while true {
    let client = try await server.accept()
    
    // Handle client in a task
    Task {
        do {
            // Read request
            let data = try await client.read(1024)
            print("Received: \(String(data: data, encoding: .utf8) ?? "")")
            
            // Send response
            let response = "Hello, Client!".data(using: .utf8)!
            try await client.write(response)
            
            await client.close()
        } catch {
            print("Client error: \(error)")
        }
    }
}
```

### UDP Socket

```swift
import Socket

// Create UDP socket
let socket = try await Socket(IPv4Protocol.udp)
let address = IPv4SocketAddress(address: .any, port: 9090)
try await socket.bind(to: address)

// Send datagram
let message = "Hello, UDP!".data(using: .utf8)!
let remoteAddress = IPv4SocketAddress(address: .init(127, 0, 0, 1), port: 9091)
try await socket.sendMessage(message, to: remoteAddress)

// Receive datagram
let (data, sender) = try await socket.receiveMessage(1024, fromAddressOf: IPv4SocketAddress.self)
print("Received from \(sender): \(String(data: data, encoding: .utf8) ?? "")")
```

### Unix Domain Socket

```swift
import Socket
import System

// Server
let path = FilePath("/tmp/my.sock")
let address = UnixSocketAddress(path: path)
let server = try await Socket(UnixProtocol.stream, bind: address)
try await server.listen()

// Client
let client = try await Socket(UnixProtocol.stream)
try await client.connect(to: address)
```

### Using Event Streams

Monitor socket events asynchronously:

```swift
import Socket

let socket = try await Socket(IPv4Protocol.tcp)

// Monitor events
Task {
    for await event in socket.event {
        switch event {
        case .read:
            let data = try await socket.read(1024)
            print("Read \(data.count) bytes")
        case .write:
            print("Socket ready for writing")
        case .error(let error):
            print("Socket error: \(error)")
        case .close:
            print("Socket closed")
            break
        default:
            break
        }
    }
}

// Use the socket...
```

### Socket Options

Configure socket behavior with type-safe options:

```swift
import Socket

let socket = try await Socket(IPv4Protocol.tcp)

// Set socket options
try socket.setOption(.reuseAddress, true)
try socket.setOption(.keepAlive, true)
try socket.setOption(.noDelay, true)  // Disable Nagle's algorithm

// Get socket option
let keepAlive: Bool = try socket[.keepAlive]
print("Keep-alive enabled: \(keepAlive)")
```

### IPv6 Support

```swift
import Socket

// IPv6 TCP socket
let socket = try await Socket(IPv6Protocol.tcp)
let address = IPv6SocketAddress(address: .loopback, port: 8080)
try await socket.connect(to: address)

// IPv6 address
let linkLocal = IPv6SocketAddress(
    address: .init("fe80::1"),
    port: 8080
)
```

## Advanced Usage

### Non-blocking Accept with Timeout

```swift
import Socket

let server = try await Socket(IPv4Protocol.tcp, bind: address)
try await server.listen()

// Accept with timeout using tasks
let acceptTask = Task {
    try await server.accept()
}

let timeoutTask = Task {
    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
    acceptTask.cancel()
}

do {
    let client = try await acceptTask.value
    timeoutTask.cancel()
    // Handle client...
} catch {
    print("Accept timed out or failed")
}
```

### Broadcasting with UDP

```swift
import Socket

let socket = try await Socket(IPv4Protocol.udp)
try socket.setOption(.broadcast, true)

// Broadcast to all hosts on the local network
let broadcastAddress = IPv4SocketAddress(
    address: .broadcast,
    port: 9999
)
try await socket.sendMessage(data, to: broadcastAddress)
```

### Raw Sockets (Requires Privileges)

```swift
import Socket

// Create raw socket (ICMP)
let socket = try await Socket(IPv4Protocol.raw)

// Send ICMP packet
let icmpPacket = createICMPPacket() // Your ICMP packet data
try await socket.write(icmpPacket)
```

## Requirements

- Swift 5.7+
- macOS 10.15+, iOS 13+, tvOS 13+, watchOS 6+, or Linux

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
