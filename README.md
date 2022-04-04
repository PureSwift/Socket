# Socket
Swift async/await based socket library

## Introduction

This library exposes an idiomatic Swift API for interacting with POSIX sockets via an async/await interface. What makes this library unique (even to the point that Swift NIO is still using a [custom socket / thread pool](https://forums.swift.org/t/swift-5-5-supports-concurrency-is-there-any-change-in-swift-nio/50940/2)) is that it was built exclusively using Swift Concurrency and doesn't use old blocking C APIs, CFSocket, DispatchIO, CFRunloop, GCD, or explicitly create a single thread outside of the Swift's global cooperative thread pool to manage the sockets and polling. 

The result is a Socket API that is optimized for async/await and built from the group up. Additionally, like the System, and Concurrency APIs, the Socket is represented as a `struct` instead of a class, greatly reducing ARC overhead. The internal state for the socket is managed by a singleton that stores both its state, and keeps an array of managed file descriptors so polling is global. 

## Goals

- Minimal overhead for Swift Async/Await
- Minimal ARC overhead, keep state outside of `Socket`
- Avoid thread explosion and overcomitting the system
- Use actors to prevent blocking threads
- Optimize polling and C / System API usage
- Low energy usage and memory overhead
