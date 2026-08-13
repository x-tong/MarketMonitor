import Foundation

enum MarketFormatters {
    static let price: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func price(_ value: Double, kind: Asset.AssetKind) -> String {
        let digits = kind == .crypto && value >= 1_000 ? 0 : (kind == .crypto ? 2 : 2)
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
