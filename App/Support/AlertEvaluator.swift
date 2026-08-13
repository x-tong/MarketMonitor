import Foundation

struct AlertEvaluation: Equatable, Sendable {
    let rule: AlertRule
    let shouldTrigger: Bool
}

enum AlertEvaluator {
    static func evaluate(
        rule: AlertRule,
        quote: Quote,
        now: Date,
        monitoringPaused: Bool,
        inQuietHours: Bool
    ) -> AlertEvaluation {
        var nextRule = rule
        guard rule.isEnabled else {
            nextRule.isActive = false
            return AlertEvaluation(rule: nextRule, shouldTrigger: false)
        }
        guard isUsableQuote(quote), quote.symbol == rule.assetSymbol else {
            return AlertEvaluation(rule: rule, shouldTrigger: false)
        }
        guard matches(rule.condition, quote: quote, threshold: rule.threshold) else {
            nextRule.isActive = false
            return AlertEvaluation(rule: nextRule, shouldTrigger: false)
        }
        guard !monitoringPaused, !inQuietHours, !rule.isActive else {
            return AlertEvaluation(rule: rule, shouldTrigger: false)
        }
        if let lastTriggeredAt = rule.lastTriggeredAt,
            now.timeIntervalSince(lastTriggeredAt) < rule.cooldown
        {
            return AlertEvaluation(rule: rule, shouldTrigger: false)
        }

        nextRule.isActive = true
        nextRule.lastTriggeredAt = now
        nextRule.lastTriggeredPrice = quote.price
        return AlertEvaluation(rule: nextRule, shouldTrigger: true)
    }

    private static func isUsableQuote(_ quote: Quote) -> Bool {
        !quote.isDemo && !quote.isStale && quote.price.isFinite && quote.price > 0
            && quote.change.isFinite && quote.changePercent.isFinite
    }

    private static func matches(_ condition: AlertRule.Condition, quote: Quote, threshold: Double) -> Bool {
        switch condition {
        case .priceAbove: return quote.price > threshold
        case .priceBelow: return quote.price < threshold
        case .percentChangeAbove: return quote.changePercent > threshold
        case .percentChangeBelow: return quote.changePercent < threshold
        }
    }
}
