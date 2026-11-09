import Foundation
import Testing
import Socket

/// Compares address text conversion against the platform's C library.
@Suite("IP Address Text Tests")
struct IPAddressTextTests {

    private func parsed(_ text: String) -> [UInt8]? {
        IPv4Address(rawValue: text)?.withUnsafeBytes { Array($0) }
    }

    private func systemParsed(_ text: String) -> [UInt8]? {
        var address = in_addr()
        let result = text.withCString { inet_pton(AF_INET, $0, &address) }
        guard result == 1 else {
            return nil
        }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private func systemFormatted(_ address: IPv4Address) -> String? {
        var buffer = [CChar](repeating: 0, count: 16)
        let success = address.withUnsafeBytes { bytes in
            inet_ntop(AF_INET, bytes.baseAddress, &buffer, 16) != nil
        }
        return success ? String(cString: buffer) : nil
    }

    private func expectMatchesSystem(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(parsed(text) == systemParsed(text), "\(text.debugDescription)", sourceLocation: sourceLocation)
    }

    private func expectFormatMatchesSystem(_ address: IPv4Address, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(address.rawValue == systemFormatted(address), sourceLocation: sourceLocation)
        #expect(IPv4Address(rawValue: address.rawValue) == address, sourceLocation: sourceLocation)
    }

    /// Every octet value in every position, with and without leading zeros.
    @Test func parsingEachOctet() {
        for value in 0 ... 255 {
            for text in ["\(value)", "0\(value)", "00\(value)"] {
                expectMatchesSystem("\(text).2.3.4")
                expectMatchesSystem("1.\(text).3.4")
                expectMatchesSystem("1.2.\(text).4")
                expectMatchesSystem("1.2.3.\(text)")
            }
        }
    }

    @Test func parsingRandomAddresses() {
        var generator = XorShift(state: 0x9E37_79B9_7F4A_7C15)
        for _ in 0 ..< 100_000 {
            let octets = (0 ..< 4).map { _ in UInt8(truncatingIfNeeded: generator.next() >> 32) }
            expectMatchesSystem(octets.map(String.init).joined(separator: "."))
        }
    }

    @Test(arguments: [
        "", ".", "...", "....", "1", "1.2", "1.2.3", "1.2.3.4.5", "1.2.3.", ".1.2.3", "1..2.3", "1.2..3",
        "256.1.1.1", "1.256.1.1", "1.1.256.1", "1.1.1.256", "999.999.999.999", "1000.1.1.1", "1.1.1.1000",
        "0000.0.0.0", "0.0.0.0000", "00.00.00.00", "000.000.000.000", "255.255.255.255", "0.0.0.0",
        " 1.2.3.4", "1.2.3.4 ", "1 .2.3.4", "1.2.3.4\n", "\t1.2.3.4",
        "0x7f.0.0.1", "0x1.2.3.4", "1.2.3.a", "a.2.3.4", "1.2.3.'", "1.2.3.-4", "+1.2.3.4", "1,2,3,4", "1/2/3/4",
        "1.2.3.4\0", "1.2.3.4\0junk", "1.2.3\0.4", "\01.2.3.4", "255.255.255.255\0", "01.2.3.4\0",
        "٣.2.3.4", "1.2.3.٤", "１.2.3.4", "1。2。3。4", "1.2.3.4é",
        "::1", "::ffff:1.2.3.4", "1:2:3:4:5:6:7:8",
        "111111111111111", "1111111111111111", "1.2.3.123456789", "123.123.123.1234", "1234567"
    ])
    func parsingEdgeCases(text: String) {
        expectMatchesSystem(text)
    }

    @Test func parsingEveryLength() {
        for length in 0 ... 20 {
            expectMatchesSystem(String(repeating: "1", count: length))
            expectMatchesSystem(String(repeating: ".", count: length))
            expectMatchesSystem("1.2.3." + String(repeating: "1", count: length))
            expectMatchesSystem(String(repeating: "1", count: length) + ".2.3.4")
        }
    }

    @Test func formattingEachOctet() {
        for value in UInt8.min ... UInt8.max {
            expectFormatMatchesSystem(IPv4Address(value, 2, 3, 4))
            expectFormatMatchesSystem(IPv4Address(1, value, 3, 4))
            expectFormatMatchesSystem(IPv4Address(1, 2, value, 4))
            expectFormatMatchesSystem(IPv4Address(1, 2, 3, value))
            expectFormatMatchesSystem(IPv4Address(value, value, value, value))
        }
    }

    @Test func ipv6Formatting() throws {
        let address = try #require(IPv6Address(rawValue: "2001:db8::1"))
        #expect(address.rawValue == "2001:db8::1")
        #expect(IPv6Address.loopback.rawValue == "::1")
        #expect(IPv6Address(rawValue: "ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255")?.rawValue != nil)
    }

    @Test func ipAddressDispatch() {
        #expect(IPAddress(rawValue: "192.168.0.1") == .v4(IPv4Address(192, 168, 0, 1)))
        #expect(IPAddress(rawValue: "::1") == .v6(.loopback))
        #expect(IPAddress(rawValue: "::ffff:1.2.3.4") == IPv6Address(rawValue: "::ffff:1.2.3.4").map(IPAddress.v6))
        #expect(IPAddress(rawValue: "") == nil)
        #expect(IPAddress(rawValue: "host.example") == nil)
        #expect(IPAddress(rawValue: "1.2.3:4") == nil)
        // text after a NUL is ignored by C, including a colon that selects IPv6 first
        let terminated = "1.2.3.4\0:"
        #expect(IPAddress(rawValue: terminated) == IPv4Address(rawValue: terminated).map(IPAddress.v4))
        #expect((IPv4Address(rawValue: terminated) != nil) == (systemParsed(terminated) != nil))
    }
}

private struct XorShift {

    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
