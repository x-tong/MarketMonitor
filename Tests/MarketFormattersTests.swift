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

    @Test("Low-priced cryptocurrencies keep meaningful precision")
    func lowPricedCryptoPrecision() {
        #expect(MarketFormatters.price(0.123456, kind: .crypto) == "0.1235")
        #expect(MarketFormatters.price(0.00001234, kind: .crypto) == "0.00001234")
        #expect(MarketFormatters.price(118_420.42, kind: .crypto) == "118,420")
    }
}
