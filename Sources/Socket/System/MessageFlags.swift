
/// Message Flags
@frozen
public struct MessageFlags: OptionSet, Hashable, Codable, Sendable {
    
  /// The raw C file permissions.
  @_alwaysEmitIntoClient
  public let rawValue: CInt

  /// Create a strongly-typed file permission from a raw C value.
  @_alwaysEmitIntoClient
  public init(rawValue: CInt) { self.rawValue = rawValue }

  @_alwaysEmitIntoClient
  private init(_ raw: CInt) { self.init(rawValue: raw) }
}

public extension MessageFlags {
    
    /// This flag requests receipt of out-of-band data that would not be received in the normal data stream.
    /// Some protocols place expedited data at the head of the normal data queue,
    /// and thus this flag cannot be used with such protocols.
    @_alwaysEmitIntoClient
    static var outOfBand: MessageFlags { MessageFlags(_MSG_OOB) }
    
    /// This flag causes the receive operation to return data from the beginning of
    /// the receive queue without removing that data from the queue.
    /// Thus, a subsequent receive call will return the same data.
    @_alwaysEmitIntoClient
    static var peek: MessageFlags { MessageFlags(_MSG_PEEK) }
    
    @_alwaysEmitIntoClient
    static var noRoute: MessageFlags { MessageFlags(_MSG_DONTROUTE) }
    
    @_alwaysEmitIntoClient
    static var endOfReadline: MessageFlags { MessageFlags(_MSG_EOR) }
    
    /// Return the real length of the packet or datagram, even when it was longer than the passed buffer.
    @_alwaysEmitIntoClient
    static var truncate: MessageFlags { MessageFlags(_MSG_TRUNC) }
    
    #if os(Linux)
    /// The caller has more data to send.
    @_alwaysEmitIntoClient
    static var more: MessageFlags { MessageFlags(_MSG_MORE) }
    
    /// Tell the link layer that forward progress happened: you
    /// got a successful reply from the other side.
    @_alwaysEmitIntoClient
    static var confirm: MessageFlags { MessageFlags(_MSG_CONFIRM) }
    #endif
}

extension MessageFlags
  : CustomStringConvertible, CustomDebugStringConvertible
{
  /// A textual representation of the file permissions.
  @inline(never)
  public var description: String {
      #if os(Linux)
      let descriptions: [(Element, StaticString)] = [
        (.outOfBand, ".outOfBand"),
        (.peek, ".peek"),
        (.noRoute, ".noRoute"),
        (.endOfReadline, ".endOfReadline"),
        (.truncate, ".truncate"),
        (.more, ".more"),
        (.confirm, ".confirm"),
      ]
      #else
      let descriptions: [(Element, StaticString)] = [
        (.outOfBand, ".outOfBand"),
        (.peek, ".peek"),
        (.noRoute, ".noRoute"),
        (.endOfReadline, ".endOfReadline"),
        (.truncate, ".truncate"),
      ]
      #endif
      return _buildDescription(descriptions)
  }

  /// A textual representation of the file permissions, suitable for debugging.
  public var debugDescription: String { self.description }
}
