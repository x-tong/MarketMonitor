import Foundation

struct MarketDataService {
    private struct ChartResponse: Decodable {
        let chart: Chart
        struct Chart: Decodable {
            let result: [Result]?
        }
        struct Result: Decodable {
            let meta: Meta
            let indicators: Indicators
        }
        struct Meta: Decodable {
            let regularMarketPrice: Double?
            let previousClose: Double?
            let chartPreviousClose: Double?
        }
        struct Indicators: Decodable {
            let quote: [QuoteSeries]
        }
        struct QuoteSeries: Decodable {
            let close: [Double?]?
        }
    }

    func fetchQuote(for asset: Asset) async throws -> Quote {
        if let marketCode = tencentMarketCode(for: asset.symbol) {
            do {
                return try await fetchTencentQuote(for: asset, marketCode: marketCode)
            } catch {
                return try await fetchYahooQuote(for: asset)
            }
        }
        return try await fetchYahooQuote(for: asset)
    }

    private func fetchTencentQuote(for asset: Asset, marketCode: String) async throws -> Quote {
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(marketCode)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("https://finance.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("MarketMonitor/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Company names use a legacy encoding, while all price fields and separators are ASCII.
        let payload = String(decoding: data, as: UTF8.self)
        guard let quoteStart = payload.firstIndex(of: "\""),
            let quoteEnd = payload.lastIndex(of: "\""), quoteStart < quoteEnd
        else {
            throw URLError(.cannotParseResponse)
        }
        let fields = payload[payload.index(after: quoteStart)..<quoteEnd].split(
            separator: "~", omittingEmptySubsequences: false)
        guard fields.count > 4,
            let price = Double(fields[3]),
            let previous = Double(fields[4]),
            price > 0
        else {
            throw URLError(.cannotParseResponse)
        }
        let change = price - previous
        return Quote(
            symbol: asset.symbol, displayName: asset.displayName, kind: asset.kind,
            price: price, change: change, changePercent: previous == 0 ? 0 : change / previous * 100,
            updatedAt: Date(), isDemo: false)
    }

    private func fetchYahooQuote(for asset: Asset) async throws -> Quote {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(asset.symbol)")!
        components.queryItems = [
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "interval", value: "1m"),
            URLQueryItem(name: "includePrePost", value: "false"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("MarketMonitor/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first else { throw URLError(.cannotParseResponse) }

        let latest =
            result.meta.regularMarketPrice
            ?? result.indicators.quote.first?.close?.compactMap { $0 }.last
        guard let price = latest else { throw URLError(.cannotParseResponse) }
        let previous = result.meta.previousClose ?? result.meta.chartPreviousClose ?? price
        let change = price - previous
        return Quote(
            symbol: asset.symbol, displayName: asset.displayName, kind: asset.kind,
            price: price, change: change, changePercent: previous == 0 ? 0 : change / previous * 100,
            updatedAt: Date(), isDemo: false)
    }

    private func tencentMarketCode(for symbol: String) -> String? {
        let mappings = [(suffix: ".SS", prefix: "sh"), (suffix: ".SZ", prefix: "sz"), (suffix: ".BJ", prefix: "bj")]
        for mapping in mappings where symbol.hasSuffix(mapping.suffix) {
            return mapping.prefix + String(symbol.dropLast(mapping.suffix.count))
        }
        guard symbol.hasSuffix(".HK") else { return nil }
        let code = String(symbol.dropLast(3))
        return "hk" + String(repeating: "0", count: max(0, 5 - code.count)) + code
    }
}
