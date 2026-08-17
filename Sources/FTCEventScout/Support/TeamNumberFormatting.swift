extension Int {
    /// FTC team numbers are identifiers, not quantities, so locale grouping
    /// separators must never be added when they are displayed.
    var teamNumberText: String { String(self) }
}
