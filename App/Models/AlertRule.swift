import Foundation

struct AlertRule: Identifiable, Codable, Hashable, Sendable {
    enum Condition: String, Codable, CaseIterable, Sendable {
        case priceAbove
        case priceBelow
        case percentChangeAbove
        case percentChangeBelow

        var title: String {
            switch self {
            case .priceAbove: return "价格高于"
            case .priceBelow: return "价格低于"
            case .percentChangeAbove: return "涨幅高于"
            case .percentChangeBelow: return "跌幅低于"
            }
        }

        var isPercentage: Bool {
            switch self {
            case .priceAbove, .priceBelow: return false
            case .percentChangeAbove, .percentChangeBelow: return true
            }
        }
    }

    let id: UUID
    let assetSymbol: String
    var condition: Condition
    var threshold: Double
    var cooldown: TimeInterval
    var isEnabled: Bool
    var isActive: Bool
    var lastTriggeredAt: Date?
    var lastTriggeredPrice: Double?

    init(
        id: UUID = UUID(),
        assetSymbol: String,
        condition: Condition,
        threshold: Double,
        cooldown: TimeInterval = 3_600,
        isEnabled: Bool = true,
        isActive: Bool = false,
        lastTriggeredAt: Date? = nil,
        lastTriggeredPrice: Double? = nil
    ) {
        self.id = id
        self.assetSymbol = assetSymbol
        self.condition = condition
        self.threshold = threshold
        self.cooldown = cooldown
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.lastTriggeredAt = lastTriggeredAt
        self.lastTriggeredPrice = lastTriggeredPrice
    }

    var isValid: Bool {
        !assetSymbol.isEmpty && threshold.isFinite && cooldown.isFinite && cooldown >= 0
    }
}
