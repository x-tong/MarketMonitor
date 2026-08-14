import SwiftUI

struct StatusBarLabel: View {
    @EnvironmentObject private var store: MarketStore

    var body: some View {
        label(at: store.displayDate)
            .help("打开行情监控")
    }

    private func label(at date: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
            if let quote = store.primaryQuote {
                Text(displayText(for: quote, at: date))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } else {
                Text("Market")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func displayText(for quote: Quote, at date: Date) -> String {
        let asset = Asset(symbol: quote.symbol, displayName: quote.displayName, kind: quote.kind)
        let quoteText = "\(asset.displaySymbol) \(MarketFormatters.price(quote.price, kind: quote.kind))"
        guard let statusText = QuoteStatusFormatter.menuBarText(for: quote, at: date) else { return quoteText }
        return "\(quoteText) \(statusText)"
    }
}
