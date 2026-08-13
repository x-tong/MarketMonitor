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

    static let assetsDefaultsKey = "market-monitor.assets"
    static let primaryDefaultsKey = "market-monitor.primary-symbol"

    private let service: any MarketDataProviding
    private let defaults: UserDefaults
    private let now: () -> Date
    private var refreshTask: Task<Void, Never>?

    init(
        service: any MarketDataProviding = MarketDataService(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        startsAutomaticRefresh: Bool = true
    ) {
        self.service = service
        self.defaults = defaults
        self.now = now

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
                } else {
                    if let previous = quotes[symbol] { quotes[symbol] = previous.markingStale() }
                    failed = true
                }
            }
        }
        isRefreshing = false
        if succeeded { lastRefresh = now() }
        if failed { lastError = "部分行情暂时不可用，已将上次数据标记为过期" }
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
        if removedPrimary { primarySymbol = assets.first?.symbol ?? "" }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(assets) { defaults.set(data, forKey: Self.assetsDefaultsKey) }
        defaults.set(primarySymbol, forKey: Self.primaryDefaultsKey)
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
