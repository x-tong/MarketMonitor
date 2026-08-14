import Foundation
import Testing

@testable import MarketMonitor

@Suite("Market store")
@MainActor
struct MarketStoreTests {
    @Test("Refresh moves quotes from demo to live to stale")
    func refreshTracksQuoteFreshness() async throws {
        let quoteDate = Date(timeIntervalSince1970: 1_990)
        let refreshDate = Date(timeIntervalSince1970: 2_000)
        let provider = ControlledMarketDataProvider(quoteDate: quoteDate)
        let defaults = try makeDefaults()
        let store = MarketStore(
            service: provider,
            defaults: defaults,
            now: { refreshDate },
            startsAutomaticRefresh: false)

        #expect(store.quotes["AAPL"]?.isDemo == true)
        #expect(store.quotes["AAPL"]?.isStale == false)

        await store.refresh()

        #expect(store.quotes["AAPL"]?.isDemo == false)
        #expect(store.quotes["AAPL"]?.isStale == false)
        #expect(store.quotes["AAPL"]?.updatedAt == quoteDate)
        #expect(store.lastRefresh == refreshDate)

        await provider.setFails(true)
        await store.refresh()

        #expect(store.quotes["AAPL"]?.isStale == true)
        #expect(store.quotes["AAPL"]?.updatedAt == quoteDate)
        #expect(store.lastRefresh == refreshDate)
        #expect(store.lastError != nil)
    }

    @Test("Refresh advances the store-owned display clock")
    func refreshAdvancesDisplayDate() async throws {
        var currentDate = Date(timeIntervalSince1970: 2_000)
        let store = MarketStore(
            service: ControlledMarketDataProvider(quoteDate: currentDate),
            defaults: try makeDefaults(),
            now: { currentDate },
            startsAutomaticRefresh: false)
        #expect(store.displayDate == currentDate)

        currentDate = currentDate.addingTimeInterval(30)
        await store.refresh()

        #expect(store.displayDate == currentDate)
    }

    @Test("Automatic refresh does not retain a discarded store")
    func automaticRefreshReleasesStore() async throws {
        let provider = RefreshTrackingProvider(delay: .milliseconds(1))
        var store: MarketStore? = MarketStore(
            service: provider,
            defaults: try makeDefaults(),
            refreshInterval: .seconds(60),
            startsAutomaticRefresh: true)
        let weakStore = WeakReference(store)
        let expectedRequests = try #require(store?.assets.count)

        await provider.waitForRequestCount(expectedRequests)
        while store?.isRefreshing == true || store?.lastRefresh == nil {
            await Task.yield()
        }
        store = nil
        for _ in 0..<20 where weakStore.value != nil {
            await Task.yield()
        }

        #expect(weakStore.value == nil)
    }

    @Test("Watchlist size and refresh concurrency stay bounded")
    func watchlistAndConcurrencyAreBounded() async throws {
        let defaults = try makeDefaults()
        let savedAssets = (0..<(MarketStore.maximumAssets + 10)).map { index in
            Asset(symbol: "TEST\(index)", displayName: "Test \(index)", kind: .stock)
        }
        defaults.set(try JSONEncoder().encode(savedAssets), forKey: MarketStore.assetsDefaultsKey)
        let provider = RefreshTrackingProvider(delay: .milliseconds(10))
        let store = MarketStore(
            service: provider,
            defaults: defaults,
            startsAutomaticRefresh: false)

        #expect(store.assets.count == MarketStore.maximumAssets)
        await store.refresh()
        let metrics = await provider.metrics()
        #expect(metrics.requestCount == MarketStore.maximumAssets)
        #expect(metrics.maximumActiveRequests <= MarketStore.maximumConcurrentRequests)

        let added = await store.add(symbol: "OVERLIMIT")
        let requestsAfterAdd = await provider.metrics().requestCount
        #expect(!added)
        #expect(requestsAfterAdd == metrics.requestCount)
        #expect(store.addError == "最多添加 \(MarketStore.maximumAssets) 个行情")
    }

    @Test("Successful add validates before persistence")
    func successfulAddPersistsValidatedAsset() async throws {
        let provider = ControlledMarketDataProvider(quoteDate: Date(timeIntervalSince1970: 1_990))
        let defaults = try makeDefaults()
        let store = MarketStore(service: provider, defaults: defaults, startsAutomaticRefresh: false)

        let added = await store.add(symbol: "MSFT")

        #expect(added)
        #expect(store.assets.contains { $0.symbol == "MSFT" })
        #expect(store.quotes["MSFT"]?.isDemo == false)
        let savedData = try #require(defaults.data(forKey: MarketStore.assetsDefaultsKey))
        let savedAssets = try JSONDecoder().decode([Asset].self, from: savedData)
        #expect(savedAssets.contains { $0.symbol == "MSFT" })
    }

    @Test("Failed add does not mutate or persist")
    func failedAddDoesNotPersist() async throws {
        let provider = ControlledMarketDataProvider(quoteDate: Date(timeIntervalSince1970: 1_000), fails: true)
        let defaults = try makeDefaults()
        let store = MarketStore(service: provider, defaults: defaults, startsAutomaticRefresh: false)

        let added = await store.add(symbol: "MSFT")

        #expect(!added)
        #expect(!store.assets.contains { $0.symbol == "MSFT" })
        #expect(store.quotes["MSFT"] == nil)
        #expect(defaults.data(forKey: MarketStore.assetsDefaultsKey) == nil)
        #expect(store.addError != nil)
    }

    @Test("Invalid provider quote does not persist")
    func invalidProviderQuoteDoesNotPersist() async throws {
        let defaults = try makeDefaults()
        let store = MarketStore(
            service: DemoMarketDataProvider(),
            defaults: defaults,
            startsAutomaticRefresh: false)

        let added = await store.add(symbol: "MSFT")

        #expect(!added)
        #expect(!store.assets.contains { $0.symbol == "MSFT" })
        #expect(defaults.data(forKey: MarketStore.assetsDefaultsKey) == nil)
        #expect(store.addError == "行情服务未返回有效数据")
    }

    @Test("Alert rules persist and notify only on trusted refreshes")
    func alertRulesPersistAndNotify() async throws {
        let quoteDate = Date(timeIntervalSince1970: 1_990)
        let provider = ControlledMarketDataProvider(quoteDate: quoteDate)
        let notifications = RecordingNotificationService()
        let defaults = try makeDefaults()
        var currentDate = Date(timeIntervalSince1970: 2_000)
        let store = MarketStore(
            service: provider,
            defaults: defaults,
            now: { currentDate },
            notificationService: notifications,
            startsAutomaticRefresh: false)
        let asset = try #require(store.assets.first(where: { $0.symbol == "AAPL" }))
        let added = await store.addAlertRule(asset: asset, condition: .priceAbove, threshold: 100, cooldown: 0)
        #expect(added)
        #expect(notifications.authorizationRequestCount == 1)
        #expect(store.notificationAuthorization == .authorized)

        await store.refresh()
        #expect(notifications.count == 1)
        #expect(store.alertRules.first?.lastTriggeredAt == currentDate)

        currentDate = currentDate.addingTimeInterval(60)
        await store.refresh()
        #expect(notifications.count == 1)

        let savedData = try #require(defaults.data(forKey: MarketStore.alertRulesDefaultsKey))
        let savedRules = try JSONDecoder().decode([AlertRule].self, from: savedData)
        #expect(savedRules.count == 1)
        #expect(savedRules[0].assetSymbol == "AAPL")
    }

    @Test("Persisted alert rules are capped")
    func alertRuleCountIsBounded() async throws {
        let defaults = try makeDefaults()
        let rules = (0..<(MarketStore.maximumAlertRules + 10)).map { index in
            AlertRule(
                assetSymbol: "AAPL",
                condition: .priceAbove,
                threshold: Double(index))
        }
        defaults.set(try JSONEncoder().encode(rules), forKey: MarketStore.alertRulesDefaultsKey)
        let store = MarketStore(defaults: defaults, startsAutomaticRefresh: false)
        let asset = try #require(store.assets.first(where: { $0.symbol == "AAPL" }))

        #expect(store.alertRules.count == MarketStore.maximumAlertRules)
        let added = await store.addAlertRule(
            asset: asset,
            condition: .priceBelow,
            threshold: -1,
            cooldown: 0)

        #expect(!added)
        #expect(store.alertRules.count == MarketStore.maximumAlertRules)
        #expect(store.alertRuleError == "最多添加 \(MarketStore.maximumAlertRules) 条提醒")
    }

    @Test("An intentionally empty watchlist survives restart")
    func emptyWatchlistPersists() async throws {
        let defaults = try makeDefaults()
        let store = MarketStore(defaults: defaults, startsAutomaticRefresh: false)

        for asset in store.assets {
            store.remove(asset)
        }

        let reloaded = MarketStore(defaults: defaults, startsAutomaticRefresh: false)
        #expect(store.assets.isEmpty)
        #expect(reloaded.assets.isEmpty)
        #expect(reloaded.primarySymbol.isEmpty)
        #expect(reloaded.quotes.isEmpty)
    }

    @Test("Denied notification permission does not consume a trigger")
    func deniedNotificationDoesNotConsumeTrigger() async throws {
        let provider = ControlledMarketDataProvider(quoteDate: Date(timeIntervalSince1970: 1_990))
        let notifications = RecordingNotificationService(requestedStatus: .denied)
        let store = MarketStore(
            service: provider,
            defaults: try makeDefaults(),
            now: { Date(timeIntervalSince1970: 2_000) },
            notificationService: notifications,
            startsAutomaticRefresh: false)
        let asset = try #require(store.assets.first(where: { $0.symbol == "AAPL" }))
        let added = await store.addAlertRule(asset: asset, condition: .priceAbove, threshold: 100, cooldown: 0)

        await store.refresh()

        #expect(added)
        #expect(notifications.authorizationRequestCount == 1)
        #expect(notifications.sendAttemptCount == 0)
        #expect(store.alertRules.first?.isActive == false)
        #expect(store.alertRules.first?.lastTriggeredAt == nil)
        #expect(store.notificationAuthorization == .denied)
        #expect(store.notificationError != nil)
    }

    @Test("Notification delivery failure leaves the rule ready to retry")
    func failedNotificationDoesNotConsumeTrigger() async throws {
        let provider = ControlledMarketDataProvider(quoteDate: Date(timeIntervalSince1970: 1_990))
        let notifications = RecordingNotificationService(
            status: .authorized,
            sendShouldFail: true)
        let store = MarketStore(
            service: provider,
            defaults: try makeDefaults(),
            now: { Date(timeIntervalSince1970: 2_000) },
            notificationService: notifications,
            startsAutomaticRefresh: false)
        let asset = try #require(store.assets.first(where: { $0.symbol == "AAPL" }))
        let added = await store.addAlertRule(asset: asset, condition: .priceAbove, threshold: 100, cooldown: 0)

        await store.refresh()
        await store.refresh()

        #expect(added)
        #expect(notifications.sendAttemptCount == 2)
        #expect(notifications.count == 0)
        #expect(store.alertRules.first?.isActive == false)
        #expect(store.alertRules.first?.lastTriggeredAt == nil)
        #expect(store.notificationError != nil)
    }

    @Test("Refresh remains locked until pending notifications finish")
    func refreshRemainsLockedDuringNotificationDelivery() async throws {
        let provider = ControlledMarketDataProvider(quoteDate: Date(timeIntervalSince1970: 1_990))
        let notifications = SuspendingNotificationService()
        let store = MarketStore(
            service: provider,
            defaults: try makeDefaults(),
            now: { Date(timeIntervalSince1970: 2_000) },
            notificationService: notifications,
            startsAutomaticRefresh: false)
        let asset = try #require(store.assets.first(where: { $0.symbol == "AAPL" }))
        let added = await store.addAlertRule(asset: asset, condition: .priceAbove, threshold: 100, cooldown: 0)

        let refresh = Task { await store.refresh() }
        await notifications.waitUntilFirstSendStarts()
        #expect(store.isRefreshing)

        await store.refresh()
        #expect(notifications.sendAttemptCount == 1)

        notifications.resumeFirstSend()
        await refresh.value
        #expect(!store.isRefreshing)
        #expect(added)
        #expect(notifications.count == 1)
    }

    @Test("Notification authorization errors remain distinct from denial")
    func notificationAuthorizationErrorIsVisible() async throws {
        let provider = ControlledMarketDataProvider(quoteDate: Date(timeIntervalSince1970: 1_990))
        let notifications = RecordingNotificationService(authorizationRequestShouldFail: true)
        let store = MarketStore(
            service: provider,
            defaults: try makeDefaults(),
            now: { Date(timeIntervalSince1970: 2_000) },
            notificationService: notifications,
            startsAutomaticRefresh: false)
        let asset = try #require(store.assets.first(where: { $0.symbol == "AAPL" }))

        let added = await store.addAlertRule(asset: asset, condition: .priceAbove, threshold: 100, cooldown: 0)
        await store.refresh()

        #expect(added)
        #expect(store.notificationAuthorization == .notDetermined)
        #expect(store.notificationError == "请求通知权限失败，请稍后重试")
        #expect(notifications.authorizationRequestCount == 2)
        #expect(notifications.sendAttemptCount == 0)
        #expect(store.alertRules.first?.lastTriggeredAt == nil)
    }

    @Test("Equal quiet-hour boundaries are rejected")
    func rejectsEqualQuietHourBoundaries() async throws {
        let store = MarketStore(defaults: try makeDefaults(), startsAutomaticRefresh: false)

        let accepted = store.setQuietHours(enabled: true, startMinute: 600, endMinute: 600)

        #expect(!accepted)
        #expect(!store.quietHoursEnabled)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "MarketStoreTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }
}

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}

private struct DemoMarketDataProvider: MarketDataProviding {
    func fetchQuote(for asset: Asset) async throws -> Quote {
        .demo(for: asset)
    }
}

private actor ControlledMarketDataProvider: MarketDataProviding {
    private let quoteDate: Date
    private var fails: Bool

    init(quoteDate: Date, fails: Bool = false) {
        self.quoteDate = quoteDate
        self.fails = fails
    }

    func setFails(_ fails: Bool) {
        self.fails = fails
    }

    func fetchQuote(for asset: Asset) async throws -> Quote {
        if fails { throw URLError(.cannotConnectToHost) }
        return Quote(
            symbol: asset.symbol,
            displayName: asset.displayName,
            kind: asset.kind,
            price: 200,
            change: 5,
            changePercent: 2.5,
            updatedAt: quoteDate,
            isDemo: false,
            isStale: false,
            marketState: .regular)
    }
}

private actor RefreshTrackingProvider: MarketDataProviding {
    private let delay: Duration
    private var activeRequests = 0
    private var maximumActiveRequests = 0
    private var requestCount = 0
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(delay: Duration) {
        self.delay = delay
    }

    func fetchQuote(for asset: Asset) async throws -> Quote {
        activeRequests += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        requestCount += 1
        resumeSatisfiedWaiters()
        defer { activeRequests -= 1 }
        try await Task.sleep(for: delay)
        return Quote(
            symbol: asset.symbol,
            displayName: asset.displayName,
            kind: asset.kind,
            price: 200,
            change: 5,
            changePercent: 2.5,
            updatedAt: Date(),
            isDemo: false,
            isStale: false,
            marketState: .regular)
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        guard requestCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((expectedCount, continuation))
        }
    }

    func metrics() -> (requestCount: Int, maximumActiveRequests: Int) {
        (requestCount, maximumActiveRequests)
    }

    private func resumeSatisfiedWaiters() {
        var pendingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in requestWaiters {
            if requestCount >= expectedCount {
                continuation.resume()
            } else {
                pendingWaiters.append((expectedCount, continuation))
            }
        }
        requestWaiters = pendingWaiters
    }
}

@MainActor
private final class RecordingNotificationService: AlertNotificationSending {
    private var status: AlertNotificationAuthorizationStatus
    private let requestedStatus: AlertNotificationAuthorizationStatus
    private let sendShouldFail: Bool
    private let authorizationRequestShouldFail: Bool
    private(set) var count = 0
    private(set) var sendAttemptCount = 0
    private(set) var authorizationRequestCount = 0

    init(
        status: AlertNotificationAuthorizationStatus = .notDetermined,
        requestedStatus: AlertNotificationAuthorizationStatus = .authorized,
        sendShouldFail: Bool = false,
        authorizationRequestShouldFail: Bool = false
    ) {
        self.status = status
        self.requestedStatus = requestedStatus
        self.sendShouldFail = sendShouldFail
        self.authorizationRequestShouldFail = authorizationRequestShouldFail
    }

    func authorizationStatus() async -> AlertNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> AlertNotificationAuthorizationStatus {
        authorizationRequestCount += 1
        if authorizationRequestShouldFail { throw URLError(.cannotConnectToHost) }
        status = requestedStatus
        return status
    }

    func send(title: String, body: String) async throws {
        sendAttemptCount += 1
        if sendShouldFail { throw URLError(.cannotCreateFile) }
        count += 1
    }
}

@MainActor
private final class SuspendingNotificationService: AlertNotificationSending {
    private var sendStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSendContinuation: CheckedContinuation<Void, Never>?
    private(set) var count = 0
    private(set) var sendAttemptCount = 0

    func authorizationStatus() async -> AlertNotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> AlertNotificationAuthorizationStatus {
        .authorized
    }

    func send(title: String, body: String) async throws {
        sendAttemptCount += 1
        if sendAttemptCount == 1 {
            let waiters = sendStartedWaiters
            sendStartedWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                firstSendContinuation = continuation
            }
        }
        count += 1
    }

    func waitUntilFirstSendStarts() async {
        guard sendAttemptCount == 0 else { return }
        await withCheckedContinuation { continuation in
            sendStartedWaiters.append(continuation)
        }
    }

    func resumeFirstSend() {
        firstSendContinuation?.resume()
        firstSendContinuation = nil
    }
}
