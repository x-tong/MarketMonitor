import Foundation
import Testing

@testable import MarketMonitor

@Suite("Alert evaluator")
struct AlertEvaluatorTests {
    private let quote = Quote(
        symbol: "AAPL",
        displayName: "Apple",
        kind: .stock,
        price: 150,
        change: 5,
        changePercent: 3.45,
        updatedAt: Date(timeIntervalSince1970: 1_000),
        isDemo: false,
        isStale: false,
        marketState: .regular)

    @Test("Triggers once and remains active while condition stays true")
    func triggersOnceUntilConditionResets() {
        let date = Date(timeIntervalSince1970: 1_000)
        let rule = AlertRule(assetSymbol: "AAPL", condition: .priceAbove, threshold: 140, cooldown: 0)
        let first = AlertEvaluator.evaluate(
            rule: rule, quote: quote, now: date, monitoringPaused: false, inQuietHours: false)
        let second = AlertEvaluator.evaluate(
            rule: first.rule, quote: quote, now: date.addingTimeInterval(10), monitoringPaused: false,
            inQuietHours: false)

        #expect(first.shouldTrigger)
        #expect(first.rule.isActive)
        #expect(first.rule.lastTriggeredPrice == quote.price)
        #expect(!second.shouldTrigger)
        #expect(second.rule.lastTriggeredAt == date)
    }

    @Test("Re-arms after condition clears but respects cooldown")
    func rearmRespectsCooldown() {
        let date = Date(timeIntervalSince1970: 1_000)
        let rule = AlertRule(
            assetSymbol: "AAPL",
            condition: .priceAbove,
            threshold: 140,
            cooldown: 3_600,
            isActive: true,
            lastTriggeredAt: date)
        let clearedQuote = Quote(
            symbol: "AAPL", displayName: "Apple", kind: .stock, price: 130, change: -1,
            changePercent: -0.7, updatedAt: date, isDemo: false, isStale: false,
            marketState: .regular)
        let cleared = AlertEvaluator.evaluate(
            rule: rule, quote: clearedQuote, now: date.addingTimeInterval(60), monitoringPaused: false,
            inQuietHours: false)
        let stillCooling = AlertEvaluator.evaluate(
            rule: cleared.rule, quote: quote, now: date.addingTimeInterval(120), monitoringPaused: false,
            inQuietHours: false)
        let refreshedQuote = Quote(
            symbol: "AAPL", displayName: "Apple", kind: .stock, price: 150, change: 5,
            changePercent: 3.45, updatedAt: date.addingTimeInterval(3_601), isDemo: false,
            isStale: false, marketState: .regular)
        let afterCooldown = AlertEvaluator.evaluate(
            rule: cleared.rule, quote: refreshedQuote, now: date.addingTimeInterval(3_601), monitoringPaused: false,
            inQuietHours: false)

        #expect(!cleared.rule.isActive)
        #expect(!stillCooling.shouldTrigger)
        #expect(afterCooldown.shouldTrigger)
    }

    @Test("Never triggers for demo, stale, delayed, closed, paused, or quiet quotes")
    func ignoresUntrustedOrSuppressedQuotes() {
        let date = Date(timeIntervalSince1970: 1_000)
        let rule = AlertRule(assetSymbol: "AAPL", condition: .priceAbove, threshold: 140)
        let demo = Quote(
            symbol: "AAPL", displayName: "Apple", kind: .stock, price: 150, change: 5,
            changePercent: 3, updatedAt: date, isDemo: true, isStale: false,
            marketState: .regular)
        let stale = quote.markingStale()
        let delayed = Quote(
            symbol: "AAPL", displayName: "Apple", kind: .stock, price: 150, change: 5,
            changePercent: 3, updatedAt: date, isDemo: false, isStale: false,
            marketState: .regular, delayMinutes: 15)
        let closed = Quote(
            symbol: "AAPL", displayName: "Apple", kind: .stock, price: 150, change: 5,
            changePercent: 3, updatedAt: date, isDemo: false, isStale: false,
            marketState: .closed)
        let old = Quote(
            symbol: "AAPL", displayName: "Apple", kind: .stock, price: 150, change: 5,
            changePercent: 3, updatedAt: date.addingTimeInterval(-601), isDemo: false, isStale: false,
            marketState: .regular)

        #expect(
            !AlertEvaluator.evaluate(rule: rule, quote: demo, now: date, monitoringPaused: false, inQuietHours: false)
                .shouldTrigger)
        #expect(
            !AlertEvaluator.evaluate(rule: rule, quote: stale, now: date, monitoringPaused: false, inQuietHours: false)
                .shouldTrigger)
        #expect(
            !AlertEvaluator.evaluate(
                rule: rule, quote: delayed, now: date, monitoringPaused: false, inQuietHours: false
            ).shouldTrigger)
        #expect(
            !AlertEvaluator.evaluate(rule: rule, quote: closed, now: date, monitoringPaused: false, inQuietHours: false)
                .shouldTrigger)
        #expect(
            !AlertEvaluator.evaluate(rule: rule, quote: old, now: date, monitoringPaused: false, inQuietHours: false)
                .shouldTrigger)
        #expect(
            !AlertEvaluator.evaluate(rule: rule, quote: quote, now: date, monitoringPaused: true, inQuietHours: false)
                .shouldTrigger)
        #expect(
            !AlertEvaluator.evaluate(rule: rule, quote: quote, now: date, monitoringPaused: false, inQuietHours: true)
                .shouldTrigger)
    }
}
