internal extension IPv4Address {

    /// Formats the address as dotted decimal text without calling into C.
    var canonicalText: String {
        // "255.255.255.255"
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 15) { buffer in
            var count = 0
            withUnsafeBytes { octets in
                for (index, octet) in octets.enumerated() {
                    if index > 0 {
                        buffer[count] = UInt8(ascii: ".")
                        count &+= 1
                    }
                    if octet >= 100 {
                        buffer[count] = UInt8(ascii: "0") &+ octet / 100
                        count &+= 1
                    }
                    if octet >= 10 {
                        buffer[count] = UInt8(ascii: "0") &+ (octet / 10) % 10
                        count &+= 1
                    }
                    buffer[count] = UInt8(ascii: "0") &+ octet % 10
                    count &+= 1
                }
            }
            return String(decoding: UnsafeBufferPointer(rebasing: buffer[..<count]), as: UTF8.self)
        }
    }
}
