import Testing

@testable import MarketMonitor

@Suite("Asset normalization")
struct AssetTests {
    @Test("Normalizes mainland symbols")
    func normalizesMainlandSymbols() {
        #expect(Asset.from(symbol: "600519")?.symbol == "600519.SS")
        #expect(Asset.from(symbol: "600519.SH")?.symbol == "600519.SS")
        #expect(Asset.from(symbol: "SZ:000001")?.symbol == "000001.SZ")
        #expect(Asset.from(symbol: "430047")?.symbol == "430047.BJ")
    }

    @Test("Normalizes Hong Kong symbols")
    func normalizesHongKongSymbols() {
        #expect(Asset.from(symbol: "700.hk")?.symbol == "0700.HK")
        #expect(Asset.from(symbol: "HK:700")?.symbol == "0700.HK")
        #expect(Asset.from(symbol: "9988.HK")?.symbol == "9988.HK")
    }

    @Test("Normalizes crypto symbols")
    func normalizesCryptoSymbols() {
        #expect(Asset.from(symbol: " btc ")?.symbol == "BTC-USD")
        #expect(Asset.from(symbol: "ETH-USD")?.symbol == "ETH-USD")
        #expect(Asset.from(symbol: "BTC")?.kind == .crypto)
    }

    @Test("Rejects blank input")
    func rejectsBlankInput() {
        #expect(Asset.from(symbol: "   \n") == nil)
    }

    @Test("Rejects symbols beyond the resource limit")
    func rejectsOversizedSymbol() {
        let symbol = String(repeating: "A", count: Asset.maximumSymbolLength + 1)

        #expect(Asset.from(symbol: symbol) == nil)
    }
}
