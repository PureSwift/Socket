extension FixedWidthInteger {
    
  @usableFromInline
  internal var networkOrder: Self {
    bigEndian
  }

  @usableFromInline
  internal init(networkOrder value: Self) {
    self.init(bigEndian: value)
  }
}
