import Foundation

enum MarketSessionState: String, Equatable, Sendable {
    case regular
    case preMarket
    case postMarket
    case closed
    case unknown

    var title: String {
        switch self {
        case .regular: return "交易中"
        case .preMarket: return "盘前"
        case .postMarket: return "盘后"
        case .closed: return "休市"
        case .unknown: return "状态未知"
        }
    }
}

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
    let marketState: MarketSessionState
    let delayMinutes: Int

    var id: String { symbol }
    var isPositive: Bool { change >= 0 }
    var isDelayed: Bool { delayMinutes > 0 }
    var isAlertEligible: Bool {
        !isDemo && !isStale && !isDelayed && marketState == .regular
    }

    func isFresh(at date: Date) -> Bool {
        (-300...600).contains(date.timeIntervalSince(updatedAt))
    }

    func isAlertEligible(at date: Date) -> Bool {
        isAlertEligible && isFresh(at: date)
    }

    init(
        symbol: String,
        displayName: String,
        kind: Asset.AssetKind,
        price: Double,
        change: Double,
        changePercent: Double,
        updatedAt: Date,
        isDemo: Bool,
        isStale: Bool,
        marketState: MarketSessionState = .unknown,
        delayMinutes: Int = 0
    ) {
        self.symbol = symbol
        self.displayName = displayName
        self.kind = kind
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.updatedAt = updatedAt
        self.isDemo = isDemo
        self.isStale = isStale
        self.marketState = marketState
        self.delayMinutes = max(delayMinutes, 0)
    }

    static func demo(for asset: Asset, updatedAt: Date = Date()) -> Quote {
        let values: [String: (Double, Double)] = [
            "AAPL": (224.58, 1.42), "NVDA": (181.32, -2.18),
            "BTC-USD": (118_420.00, 2_840.00), "ETH-USD": (4_160.40, -96.10),
        ]
        let value = values[asset.symbol] ?? (100.00, 0.85)
        return Quote(
            symbol: asset.symbol, displayName: asset.displayName, kind: asset.kind,
            price: value.0, change: value.1, changePercent: value.1 / value.0 * 100,
            updatedAt: updatedAt, isDemo: true, isStale: false, marketState: .unknown)
    }

    func markingStale() -> Quote {
        Quote(
            symbol: symbol, displayName: displayName, kind: kind,
            price: price, change: change, changePercent: changePercent,
            updatedAt: updatedAt, isDemo: isDemo, isStale: true,
            marketState: marketState, delayMinutes: delayMinutes)
    }
}
