import SwiftUI

struct StatusBarLabel: View {
    @EnvironmentObject private var store: MarketStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
            if let quote = store.primaryQuote {
                Text(Asset(symbol: quote.symbol, displayName: quote.displayName, kind: quote.kind).displaySymbol)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(MarketFormatters.price(quote.price, kind: quote.kind))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Image(systemName: quote.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(quote.isPositive ? .green : .red)
            } else {
                Text("Market")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .help("打开行情监控")
    }
}
