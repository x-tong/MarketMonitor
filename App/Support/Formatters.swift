import Foundation

enum MarketFormatters {
    static func price(_ value: Double, kind: Asset.AssetKind) -> String {
        let digits: Int
        switch (kind, abs(value)) {
        case (.crypto, 1_000...): digits = 0
        case (.crypto, 1...): digits = 2
        case (.crypto, 0.01...): digits = 4
        case (.crypto, 0...): digits = 8
        default: digits = 2
        }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func signed(_ value: Double, kind: Asset.AssetKind) -> String {
        let prefix = value >= 0 ? "+" : "-"
        return prefix + price(abs(value), kind: kind)
    }

    static func percent(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return prefix + value.formatted(.number.precision(.fractionLength(2))) + "%"
    }
}
