import Combine
import Foundation

@MainActor
final class MarketStore: ObservableObject {
    @Published private(set) var assets: [Asset]
    @Published private(set) var primarySymbol: String
    @Published private(set) var quotes: [String: Quote] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAdding = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var addError: String?
    @Published private(set) var alertRules: [AlertRule]
    @Published private(set) var monitoringPaused: Bool
    @Published private(set) var quietHoursEnabled: Bool
    @Published private(set) var quietHoursStartMinute: Int
    @Published private(set) var quietHoursEndMinute: Int

    static let assetsDefaultsKey = "market-monitor.assets"
    static let primaryDefaultsKey = "market-monitor.primary-symbol"
    static let alertRulesDefaultsKey = "market-monitor.alert-rules"
    static let monitoringPausedDefaultsKey = "market-monitor.monitoring-paused"
    static let quietHoursEnabledDefaultsKey = "market-monitor.quiet-hours-enabled"
    static let quietHoursStartDefaultsKey = "market-monitor.quiet-hours-start"
    static let quietHoursEndDefaultsKey = "market-monitor.quiet-hours-end"

    private let service: any MarketDataProviding
    private let defaults: UserDefaults
    private let now: () -> Date
    private let notificationService: any AlertNotificationSending
    private var refreshTask: Task<Void, Never>?
    private var notificationAuthorizationRequested = false

    init(
        service: any MarketDataProviding = MarketDataService(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        notificationService: any AlertNotificationSending = UserNotificationService(),
        startsAutomaticRefresh: Bool = true
    ) {
        self.service = service
        self.defaults = defaults
        self.now = now
        self.notificationService = notificationService

        let loadedAssets: [Asset]
        if let data = defaults.data(forKey: Self.assetsDefaultsKey),
            let saved = try? JSONDecoder().decode([Asset].self, from: data), !saved.isEmpty
        {
            loadedAssets = saved
        } else {
            loadedAssets = Asset.defaults
        }
        assets = loadedAssets
        let savedPrimary = defaults.string(forKey: Self.primaryDefaultsKey)
        primarySymbol =
            savedPrimary.flatMap { candidate in
                loadedAssets.contains { $0.symbol == candidate } ? candidate : nil
            } ?? loadedAssets.first?.symbol ?? ""
        let savedRules =
            (try? defaults.data(forKey: Self.alertRulesDefaultsKey).flatMap {
                try JSONDecoder().decode([AlertRule].self, from: $0)
            }) ?? nil
        alertRules =
            savedRules?.filter { rule in
                rule.isValid && loadedAssets.contains { $0.symbol == rule.assetSymbol }
            } ?? []
        monitoringPaused = defaults.bool(forKey: Self.monitoringPausedDefaultsKey)
        quietHoursEnabled = defaults.bool(forKey: Self.quietHoursEnabledDefaultsKey)
        quietHoursStartMinute = min(
            max(defaults.object(forKey: Self.quietHoursStartDefaultsKey) as? Int ?? 22 * 60, 0), 1_439)
        quietHoursEndMinute = min(
            max(defaults.object(forKey: Self.quietHoursEndDefaultsKey) as? Int ?? 7 * 60, 0), 1_439)
        let initialDate = now()
        for asset in loadedAssets { quotes[asset.symbol] = .demo(for: asset, updatedAt: initialDate) }
        if startsAutomaticRefresh {
            refreshTask = Task { [weak self] in
                guard let self else { return }
                await self.refresh()
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        break
                    }
                    if !Task.isCancelled { await self.refresh() }
                }
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var primaryQuote: Quote? {
        quotes[primarySymbol] ?? assets.lazy.compactMap { self.quotes[$0.symbol] }.first
    }

    func isPrimary(_ asset: Asset) -> Bool {
        asset.symbol == primarySymbol
    }

    func setPrimary(_ asset: Asset) {
        guard assets.contains(asset), primarySymbol != asset.symbol else { return }
        primarySymbol = asset.symbol
        persist()
    }

    func setPrimary(symbol: String) {
        guard let asset = assets.first(where: { $0.symbol == symbol }) else { return }
        setPrimary(asset)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        var failed = false
        var succeeded = false
        var notifications: [(String, String)] = []
        let service = service
        await withTaskGroup(of: (String, Quote?).self) { group in
            for asset in assets {
                group.addTask {
                    do { return (asset.symbol, try await service.fetchQuote(for: asset)) } catch {
                        return (asset.symbol, nil)
                    }
                }
            }
            for await (symbol, quote) in group {
                guard let asset = assets.first(where: { $0.symbol == symbol }) else { continue }
                if let quote, isValidLiveQuote(quote, for: asset) {
                    quotes[symbol] = quote
                    succeeded = true
                    notifications.append(contentsOf: evaluateAlerts(for: quote, at: now()))
                } else {
                    if let previous = quotes[symbol] { quotes[symbol] = previous.markingStale() }
                    failed = true
                }
            }
        }
        isRefreshing = false
        if succeeded { lastRefresh = now() }
        if failed { lastError = "部分行情暂时不可用，已将上次数据标记为过期" }
        if !notifications.isEmpty, !notificationAuthorizationRequested {
            notificationAuthorizationRequested = true
            await notificationService.requestAuthorization()
        }
        for (title, body) in notifications {
            await notificationService.send(title: title, body: body)
        }
    }

    @discardableResult
    func add(symbol: String) async -> Bool {
        guard !isAdding else { return false }
        guard let asset = Asset.from(symbol: symbol) else {
            addError = "请输入有效的行情代码"
            return false
        }
        guard !assets.contains(asset) else {
            addError = "该行情已在列表中"
            return false
        }

        isAdding = true
        addError = nil
        defer { isAdding = false }

        let quote: Quote
        do {
            quote = try await service.fetchQuote(for: asset)
        } catch {
            addError = "无法验证该代码，请检查代码或稍后重试"
            return false
        }
        guard isValidLiveQuote(quote, for: asset) else {
            addError = "行情服务未返回有效数据"
            return false
        }
        guard !assets.contains(asset) else {
            addError = "该行情已在列表中"
            return false
        }

        assets.append(asset)
        quotes[asset.symbol] = quote
        if primarySymbol.isEmpty { primarySymbol = asset.symbol }
        persist()
        return true
    }

    func remove(_ asset: Asset) {
        let removedPrimary = isPrimary(asset)
        assets.removeAll { $0.id == asset.id }
        quotes.removeValue(forKey: asset.symbol)
        alertRules.removeAll { $0.assetSymbol == asset.symbol }
        if removedPrimary { primarySymbol = assets.first?.symbol ?? "" }
        persist()
    }

    @discardableResult
    func addAlertRule(
        asset: Asset,
        condition: AlertRule.Condition,
        threshold: Double,
        cooldown: TimeInterval
    ) -> Bool {
        guard assets.contains(asset), threshold.isFinite, cooldown.isFinite, cooldown >= 0 else { return false }
        guard
            !alertRules.contains(where: {
                $0.assetSymbol == asset.symbol && $0.condition == condition && $0.threshold == threshold
            })
        else { return false }
        alertRules.append(
            AlertRule(
                assetSymbol: asset.symbol,
                condition: condition,
                threshold: threshold,
                cooldown: cooldown))
        persist()
        return true
    }

    func removeAlertRule(_ rule: AlertRule) {
        alertRules.removeAll { $0.id == rule.id }
        persist()
    }

    func setAlertRuleEnabled(_ rule: AlertRule, isEnabled: Bool) {
        guard let index = alertRules.firstIndex(where: { $0.id == rule.id }) else { return }
        alertRules[index].isEnabled = isEnabled
        if !isEnabled { alertRules[index].isActive = false }
        persist()
    }

    func setMonitoringPaused(_ paused: Bool) {
        monitoringPaused = paused
        persist()
    }

    func setQuietHours(enabled: Bool, startMinute: Int, endMinute: Int) {
        quietHoursEnabled = enabled
        quietHoursStartMinute = min(max(startMinute, 0), 1_439)
        quietHoursEndMinute = min(max(endMinute, 0), 1_439)
        persist()
    }

    func isInQuietHours(at date: Date) -> Bool {
        guard quietHoursEnabled else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if quietHoursStartMinute == quietHoursEndMinute { return true }
        if quietHoursStartMinute < quietHoursEndMinute {
            return (quietHoursStartMinute..<quietHoursEndMinute).contains(minute)
        }
        return minute >= quietHoursStartMinute || minute < quietHoursEndMinute
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(assets) { defaults.set(data, forKey: Self.assetsDefaultsKey) }
        defaults.set(primarySymbol, forKey: Self.primaryDefaultsKey)
        if let data = try? JSONEncoder().encode(alertRules) { defaults.set(data, forKey: Self.alertRulesDefaultsKey) }
        defaults.set(monitoringPaused, forKey: Self.monitoringPausedDefaultsKey)
        defaults.set(quietHoursEnabled, forKey: Self.quietHoursEnabledDefaultsKey)
        defaults.set(quietHoursStartMinute, forKey: Self.quietHoursStartDefaultsKey)
        defaults.set(quietHoursEndMinute, forKey: Self.quietHoursEndDefaultsKey)
    }

    private func evaluateAlerts(for quote: Quote, at date: Date) -> [(String, String)] {
        var notifications: [(String, String)] = []
        var didChange = false
        for index in alertRules.indices where alertRules[index].assetSymbol == quote.symbol {
            let evaluation = AlertEvaluator.evaluate(
                rule: alertRules[index],
                quote: quote,
                now: date,
                monitoringPaused: monitoringPaused,
                inQuietHours: isInQuietHours(at: date))
            if evaluation.rule != alertRules[index] {
                alertRules[index] = evaluation.rule
                didChange = true
            }
            if evaluation.shouldTrigger {
                let assetName = assets.first(where: { $0.symbol == quote.symbol })?.displayName ?? quote.symbol
                let value =
                    evaluation.rule.condition.isPercentage
                    ? MarketFormatters.percent(quote.changePercent)
                    : MarketFormatters.price(quote.price, kind: quote.kind)
                notifications.append(("\(assetName) 提醒", "\(evaluation.rule.condition.title) \(value)"))
            }
        }
        if didChange { persist() }
        return notifications
    }

    private func isValidLiveQuote(_ quote: Quote, for asset: Asset) -> Bool {
        quote.symbol == asset.symbol
            && quote.kind == asset.kind
            && quote.price.isFinite
            && quote.price > 0
            && quote.change.isFinite
            && quote.changePercent.isFinite
            && !quote.isDemo
            && !quote.isStale
    }
}
