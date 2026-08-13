import Testing

@testable import MarketMonitor

@Suite("Market formatters")
struct MarketFormattersTests {
    @Test("Signed values preserve direction")
    func signedValuePreservesDirection() {
        #expect(MarketFormatters.signed(2.18, kind: .stock) == "+2.18")
        #expect(MarketFormatters.signed(-2.18, kind: .stock) == "-2.18")
    }

    @Test("Percentages include direction")
    func percentIncludesDirection() {
        #expect(MarketFormatters.percent(0.92) == "+0.92%")
        #expect(MarketFormatters.percent(-4.46) == "-4.46%")
    }
}
