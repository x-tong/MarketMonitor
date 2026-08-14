import Foundation

enum QuoteStatusFormatter {
    static func labels(for quote: Quote, at date: Date) -> [String] {
        if quote.isDemo {
            return quote.isStale ? ["模拟", "已过期"] : ["模拟"]
        }
        if quote.isStale || (quote.marketState == .regular && !quote.isFresh(at: date)) {
            return ["已过期"]
        }

        var labels: [String] = []
        if quote.isDelayed { labels.append("延迟 \(quote.delayMinutes) 分钟") }
        labels.append(quote.marketState.title)
        return labels
    }

    static func detailText(for quote: Quote, at date: Date, calendar: Calendar = .current) -> String {
        let time = quote.updatedAt.formatted(
            date: calendar.isDate(quote.updatedAt, inSameDayAs: date) ? .omitted : .abbreviated,
            time: .shortened)
        return (labels(for: quote, at: date) + [time]).joined(separator: " · ")
    }

    static func shortText(for quote: Quote, at date: Date) -> String {
        if quote.isDemo && quote.isStale { return "模拟/过期" }
        if quote.isDemo { return "模拟" }
        if quote.isStale || (quote.marketState == .regular && !quote.isFresh(at: date)) { return "过期" }
        if quote.isDelayed { return "延迟\(quote.delayMinutes)m" }
        return quote.marketState.title
    }
}
