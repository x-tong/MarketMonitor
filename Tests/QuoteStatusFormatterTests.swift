import Foundation
import Testing

@testable import MarketMonitor

@Suite("Quote status formatter")
struct QuoteStatusFormatterTests {
    @Test("Expired quotes do not also claim to be trading")
    func expiredOverridesTradingState() {
        let date = Date(timeIntervalSince1970: 2_000)
        let stale = quote(updatedAt: date, isStale: true, marketState: .regular)
        let aged = quote(updatedAt: date.addingTimeInterval(-601), marketState: .regular)

        #expect(QuoteStatusFormatter.labels(for: stale, at: date) == ["已过期"])
        #expect(QuoteStatusFormatter.labels(for: aged, at: date) == ["已过期"])
        #expect(QuoteStatusFormatter.shortText(for: aged, at: date) == "过期")
    }

    @Test("Closed quotes retain their market state regardless of age")
    func closedQuoteRetainsState() {
        let date = Date(timeIntervalSince1970: 2_000)
        let closed = quote(updatedAt: date.addingTimeInterval(-10_000), marketState: .closed)

        #expect(QuoteStatusFormatter.labels(for: closed, at: date) == ["休市"])
        #expect(QuoteStatusFormatter.shortText(for: closed, at: date) == "休市")
    }

    @Test("Unknown session metadata does not add a visible status label")
    func unknownSessionMetadataIsOmitted() {
        let date = Date(timeIntervalSince1970: 2_000)
        let unknown = quote(updatedAt: date, marketState: .unknown)

        #expect(QuoteStatusFormatter.labels(for: unknown, at: date).isEmpty)
    }

    @Test("Menu bar omits session metadata that does not affect price trust")
    func menuBarOmitsSessionMetadata() {
        let date = Date(timeIntervalSince1970: 2_000)
        let unknown = quote(updatedAt: date, marketState: .unknown)
        let closed = quote(updatedAt: date.addingTimeInterval(-10_000), marketState: .closed)

        #expect(QuoteStatusFormatter.menuBarText(for: unknown, at: date) == nil)
        #expect(QuoteStatusFormatter.menuBarText(for: closed, at: date) == nil)
    }

    @Test("Menu bar retains data trust warnings")
    func menuBarRetainsTrustWarnings() {
        let date = Date(timeIntervalSince1970: 2_000)
        let stale = quote(updatedAt: date, isStale: true, marketState: .unknown)
        let delayed = quote(updatedAt: date, delayMinutes: 15, marketState: .unknown)

        #expect(QuoteStatusFormatter.menuBarText(for: stale, at: date) == "过期")
        #expect(QuoteStatusFormatter.menuBarText(for: delayed, at: date) == "延迟15m")
    }

    private func quote(
        updatedAt: Date,
        isStale: Bool = false,
        delayMinutes: Int = 0,
        marketState: MarketSessionState
    ) -> Quote {
        Quote(
            symbol: "AAPL",
            displayName: "Apple",
            kind: .stock,
            price: 150,
            change: 5,
            changePercent: 3.45,
            updatedAt: updatedAt,
            isDemo: false,
            isStale: isStale,
            marketState: marketState,
            delayMinutes: delayMinutes)
    }
}
