import Foundation
import Testing

@testable import MarketMonitor

@Suite("Market store")
@MainActor
struct MarketStoreTests {
    @Test("Refresh moves quotes from demo to live to stale")
    func refreshTracksQuoteFreshness() async throws {
        let quoteDate = Date(timeIntervalSince1970: 1_000)
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

    @Test("Successful add validates before persistence")
    func successfulAddPersistsValidatedAsset() async throws {
        let provider = ControlledMarketDataProvider(quoteDate: Date(timeIntervalSince1970: 1_000))
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
        let quoteDate = Date(timeIntervalSince1970: 1_000)
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
        #expect(store.addAlertRule(asset: asset, condition: .priceAbove, threshold: 100, cooldown: 0))

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

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "MarketStoreTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
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
            isStale: false)
    }
}

@MainActor
private final class RecordingNotificationService: AlertNotificationSending {
    private(set) var count = 0

    func requestAuthorization() async {}

    func send(title: String, body: String) async {
        count += 1
    }
}
