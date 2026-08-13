import Combine
import Foundation

@MainActor
final class MarketStore: ObservableObject {
    @Published private(set) var assets: [Asset]
    @Published private(set) var primarySymbol: String
    @Published private(set) var quotes: [String: Quote] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastError: String?

    private let service = MarketDataService()
    private let defaultsKey = "market-monitor.assets"
    private let primaryKey = "market-monitor.primary-symbol"
    private var refreshTask: Task<Void, Never>?

    init() {
        let loadedAssets: [Asset]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
            let saved = try? JSONDecoder().decode([Asset].self, from: data), !saved.isEmpty
        {
            loadedAssets = saved
        } else {
            loadedAssets = Asset.defaults
        }
        assets = loadedAssets
        let savedPrimary = UserDefaults.standard.string(forKey: primaryKey)
        primarySymbol =
            savedPrimary.flatMap { candidate in
                loadedAssets.contains { $0.symbol == candidate } ? candidate : nil
            } ?? loadedAssets.first?.symbol ?? ""
        for asset in loadedAssets { quotes[asset.symbol] = .demo(for: asset) }
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
        await withTaskGroup(of: (String, Quote?).self) { group in
            for asset in assets {
                group.addTask {
                    do { return (asset.symbol, try await self.service.fetchQuote(for: asset)) } catch {
                        return (asset.symbol, nil)
                    }
                }
            }
            for await (symbol, quote) in group {
                if let quote { quotes[symbol] = quote } else { failed = true }
            }
        }
        isRefreshing = false
        lastRefresh = Date()
        if failed { lastError = "部分行情暂时不可用，已保留上次数据" }
    }

    func add(symbol: String) {
        guard let asset = Asset.from(symbol: symbol), !assets.contains(asset) else { return }
        assets.append(asset)
        quotes[asset.symbol] = .demo(for: asset)
        if primarySymbol.isEmpty { primarySymbol = asset.symbol }
        persist()
        Task { await refresh() }
    }

    func remove(_ asset: Asset) {
        let removedPrimary = isPrimary(asset)
        assets.removeAll { $0.id == asset.id }
        quotes.removeValue(forKey: asset.symbol)
        if removedPrimary { primarySymbol = assets.first?.symbol ?? "" }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(assets) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        UserDefaults.standard.set(primarySymbol, forKey: primaryKey)
    }
}
