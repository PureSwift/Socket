internal extension IPv4Address {

    /// Parses canonical dotted decimal text without calling into C.
    ///
    /// Only four segments of one to three digits, each no greater than 255 and without
    /// leading zeros, are handled. Anything else returns `nil`, which means *not handled*
    /// rather than *invalid*: callers must defer to `inet_pton`, whose rules differ between
    /// platforms.
    @inline(__always)
    static func parseCanonical(_ text: UnsafeBufferPointer<UInt8>) -> IPv4Address? {
        // "0.0.0.0" through "255.255.255.255"
        guard text.count >= 7, text.count <= 15 else {
            return nil
        }
        var index = 0
        var address: UInt32 = 0
        for segment in 0 ..< 4 {
            let start = index
            var value: UInt32 = 0
            while index < text.count, index &- start < 3 {
                let digit = text[index] &- UInt8(ascii: "0")
                guard digit <= 9 else {
                    break
                }
                value = value &* 10 &+ UInt32(digit)
                index &+= 1
            }
            let length = index &- start
            guard length > 0, value <= 255, length == 1 || text[start] != UInt8(ascii: "0") else {
                return nil
            }
            address = address << 8 | value
            if segment < 3 {
                guard index < text.count, text[index] == UInt8(ascii: ".") else {
                    return nil
                }
                index &+= 1
            }
        }
        guard index == text.count else {
            return nil
        }
        return IPv4Address(
            UInt8(truncatingIfNeeded: address >> 24),
            UInt8(truncatingIfNeeded: address >> 16),
            UInt8(truncatingIfNeeded: address >> 8),
            UInt8(truncatingIfNeeded: address)
        )
    }
}
