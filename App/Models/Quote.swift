import Foundation

struct Quote: Identifiable, Equatable, Sendable {
    let symbol: String
    let displayName: String
    let kind: Asset.AssetKind
    let price: Double
    let change: Double
    let changePercent: Double
    let updatedAt: Date
    let isDemo: Bool
    let isStale: Bool

    var id: String { symbol }
    var isPositive: Bool { change >= 0 }

    static func demo(for asset: Asset, updatedAt: Date = Date()) -> Quote {
        let values: [String: (Double, Double)] = [
            "AAPL": (224.58, 1.42), "NVDA": (181.32, -2.18),
            "BTC-USD": (118_420.00, 2_840.00), "ETH-USD": (4_160.40, -96.10),
        ]
        let value = values[asset.symbol] ?? (100.00, 0.85)
        return Quote(
            symbol: asset.symbol, displayName: asset.displayName, kind: asset.kind,
            price: value.0, change: value.1, changePercent: value.1 / value.0 * 100,
            updatedAt: updatedAt, isDemo: true, isStale: false)
    }

    func markingStale() -> Quote {
        Quote(
            symbol: symbol, displayName: displayName, kind: kind,
            price: price, change: change, changePercent: changePercent,
            updatedAt: updatedAt, isDemo: isDemo, isStale: true)
    }
}
