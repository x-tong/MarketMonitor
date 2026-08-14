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
    @Published private(set) var notificationAuthorization: AlertNotificationAuthorizationStatus = .unknown
    @Published private(set) var notificationError: String?
    @Published private(set) var alertRuleError: String?
    @Published private(set) var displayDate: Date

    static let maximumAssets = 50
    static let maximumAlertRules = 200
    static let maximumConcurrentRequests = 6
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
    private let refreshInterval: Duration
    private var refreshTask: Task<Void, Never>?

    private struct PendingAlert {
        let ruleID: UUID
        let triggeredRule: AlertRule
        let title: String
        let body: String
    }

    init(
        service: any MarketDataProviding = MarketDataService(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        notificationService: any AlertNotificationSending = UserNotificationService(),
        refreshInterval: Duration = .seconds(30),
        startsAutomaticRefresh: Bool = true
    ) {
        self.service = service
        self.defaults = defaults
        self.now = now
        self.notificationService = notificationService
        self.refreshInterval = refreshInterval

        let loadedAssets: [Asset]
        if let data = defaults.data(forKey: Self.assetsDefaultsKey),
            let saved = try? JSONDecoder().decode([Asset].self, from: data)
        {
            var seenSymbols = Set<String>()
            var boundedAssets: [Asset] = []
            for asset in saved {
                guard asset.isValidPersistedAsset, seenSymbols.insert(asset.symbol).inserted else { continue }
                boundedAssets.append(asset)
                if boundedAssets.count == Self.maximumAssets { break }
            }
            loadedAssets = boundedAssets
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
        var seenRuleIDs = Set<UUID>()
        var boundedRules: [AlertRule] = []
        for rule in savedRules ?? [] {
            guard rule.isValid,
                loadedAssets.contains(where: { $0.symbol == rule.assetSymbol }),
                seenRuleIDs.insert(rule.id).inserted
            else { continue }
            boundedRules.append(rule)
            if boundedRules.count == Self.maximumAlertRules { break }
        }
        alertRules = boundedRules
        monitoringPaused = defaults.bool(forKey: Self.monitoringPausedDefaultsKey)
        quietHoursEnabled = defaults.bool(forKey: Self.quietHoursEnabledDefaultsKey)
        quietHoursStartMinute = min(
            max(defaults.object(forKey: Self.quietHoursStartDefaultsKey) as? Int ?? 22 * 60, 0), 1_439)
        quietHoursEndMinute = min(
            max(defaults.object(forKey: Self.quietHoursEndDefaultsKey) as? Int ?? 7 * 60, 0), 1_439)
        let initialDate = now()
        displayDate = initialDate
        for asset in loadedAssets { quotes[asset.symbol] = .demo(for: asset, updatedAt: initialDate) }
        if startsAutomaticRefresh {
            refreshTask = Task { [weak self, refreshInterval] in
                await self?.refresh()
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: refreshInterval)
                    } catch {
                        break
                    }
                    if !Task.isCancelled { await self?.refresh() }
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
        displayDate = now()
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil
        var failed = false
        var succeeded = false
        var pendingAlerts: [PendingAlert] = []
        let service = service
        let refreshAssets = assets
        await withTaskGroup(of: (Asset, Quote?).self) { group in
            var iterator = refreshAssets.makeIterator()
            for _ in 0..<min(Self.maximumConcurrentRequests, refreshAssets.count) {
                guard let asset = iterator.next() else { break }
                group.addTask {
                    do { return (asset, try await service.fetchQuote(for: asset)) } catch {
                        return (asset, nil)
                    }
                }
            }
            while let (asset, quote) = await group.next() {
                if let nextAsset = iterator.next() {
                    group.addTask {
                        do { return (nextAsset, try await service.fetchQuote(for: nextAsset)) } catch {
                            return (nextAsset, nil)
                        }
                    }
                }
                guard assets.contains(asset) else { continue }
                if let quote, isValidProviderQuote(quote, for: asset) {
                    quotes[asset.symbol] = quote
                    succeeded = true
                    pendingAlerts.append(contentsOf: evaluateAlerts(for: quote, at: now()))
                } else {
                    if let previous = quotes[asset.symbol] {
                        quotes[asset.symbol] = previous.markingStale()
                    }
                    failed = true
                }
            }
        }
        if succeeded { lastRefresh = now() }
        if failed { lastError = "部分行情暂时不可用，已将上次数据标记为过期" }
        await deliverAlerts(pendingAlerts)
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
        guard assets.count < Self.maximumAssets else {
            addError = "最多添加 \(Self.maximumAssets) 个行情"
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
        guard isValidProviderQuote(quote, for: asset) else {
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
    ) async -> Bool {
        guard assets.contains(asset), threshold.isFinite, cooldown.isFinite, cooldown >= 0 else {
            alertRuleError = "提醒参数无效"
            return false
        }
        guard alertRules.count < Self.maximumAlertRules else {
            alertRuleError = "最多添加 \(Self.maximumAlertRules) 条提醒"
            return false
        }
        guard
            !alertRules.contains(where: {
                $0.assetSymbol == asset.symbol && $0.condition == condition && $0.threshold == threshold
            })
        else {
            alertRuleError = "相同提醒已存在"
            return false
        }
        alertRuleError = nil
        alertRules.append(
            AlertRule(
                assetSymbol: asset.symbol,
                condition: condition,
                threshold: threshold,
                cooldown: cooldown))
        persist()
        await updateNotificationAuthorization(requestIfNeeded: true)
        return true
    }

    func requestNotificationAuthorization() async {
        await updateNotificationAuthorization(requestIfNeeded: true)
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

    @discardableResult
    func setQuietHours(enabled: Bool, startMinute: Int, endMinute: Int) -> Bool {
        guard (0..<1_440).contains(startMinute), (0..<1_440).contains(endMinute),
            !enabled || startMinute != endMinute
        else { return false }
        quietHoursEnabled = enabled
        quietHoursStartMinute = startMinute
        quietHoursEndMinute = endMinute
        persist()
        return true
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

    private func evaluateAlerts(for quote: Quote, at date: Date) -> [PendingAlert] {
        var pendingAlerts: [PendingAlert] = []
        var didChange = false
        for index in alertRules.indices where alertRules[index].assetSymbol == quote.symbol {
            let evaluation = AlertEvaluator.evaluate(
                rule: alertRules[index],
                quote: quote,
                now: date,
                monitoringPaused: monitoringPaused,
                inQuietHours: isInQuietHours(at: date))
            if !evaluation.shouldTrigger, evaluation.rule != alertRules[index] {
                alertRules[index] = evaluation.rule
                didChange = true
            }
            if evaluation.shouldTrigger {
                let assetName = assets.first(where: { $0.symbol == quote.symbol })?.displayName ?? quote.symbol
                let value =
                    evaluation.rule.condition.isPercentage
                    ? MarketFormatters.percent(quote.changePercent)
                    : MarketFormatters.price(quote.price, kind: quote.kind)
                pendingAlerts.append(
                    PendingAlert(
                        ruleID: evaluation.rule.id,
                        triggeredRule: evaluation.rule,
                        title: "\(assetName) 提醒",
                        body: "\(evaluation.rule.condition.title) \(value)"))
            }
        }
        if didChange { persist() }
        return pendingAlerts
    }

    private func deliverAlerts(_ pendingAlerts: [PendingAlert]) async {
        guard !pendingAlerts.isEmpty else { return }
        let status = await updateNotificationAuthorization(requestIfNeeded: true)
        guard status == .authorized else { return }

        var didChange = false
        for pendingAlert in pendingAlerts {
            do {
                try await notificationService.send(title: pendingAlert.title, body: pendingAlert.body)
                guard let index = alertRules.firstIndex(where: { $0.id == pendingAlert.ruleID }) else { continue }
                alertRules[index].lastTriggeredAt = pendingAlert.triggeredRule.lastTriggeredAt
                alertRules[index].lastTriggeredPrice = pendingAlert.triggeredRule.lastTriggeredPrice
                alertRules[index].isActive = alertRules[index].isEnabled
                didChange = true
            } catch {
                notificationError = "通知发送失败，将在下次行情刷新时重试"
            }
        }
        if didChange { persist() }
    }

    @discardableResult
    private func updateNotificationAuthorization(
        requestIfNeeded: Bool
    ) async -> AlertNotificationAuthorizationStatus {
        var status = await notificationService.authorizationStatus()
        if requestIfNeeded, status == .notDetermined {
            do {
                status = try await notificationService.requestAuthorization()
            } catch {
                notificationAuthorization = status
                notificationError = "请求通知权限失败，请稍后重试"
                return status
            }
        }
        notificationAuthorization = status
        switch status {
        case .authorized:
            notificationError = nil
        case .denied:
            notificationError = "通知权限未开启，请在系统设置中允许 MarketMonitor 通知"
        case .notDetermined:
            notificationError = "尚未获得通知权限，价格提醒暂时不会触发"
        case .unknown:
            notificationError = nil
        }
        return status
    }

    private func isValidProviderQuote(_ quote: Quote, for asset: Asset) -> Bool {
        quote.symbol == asset.symbol
            && quote.kind == asset.kind
            && quote.price.isFinite
            && quote.price > 0
            && quote.change.isFinite
            && quote.changePercent.isFinite
            && quote.delayMinutes >= 0
            && !quote.isDemo
            && !quote.isStale
    }
}
