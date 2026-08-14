import Foundation

struct MarketDataHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol MarketDataProviding: Sendable {
    func fetchQuote(for asset: Asset) async throws -> Quote
}

struct MarketDataService: MarketDataProviding {
    typealias Loader = @Sendable (URLRequest) async throws -> MarketDataHTTPResponse

    static let maximumResponseBytes = 1_048_576

    private let loader: Loader
    private let now: @Sendable () -> Date
    private let requestTimeout: Duration

    init(
        loader: @escaping Loader = MarketDataService.liveLoader,
        now: @escaping @Sendable () -> Date = Date.init,
        requestTimeout: Duration = .seconds(10)
    ) {
        self.loader = loader
        self.now = now
        self.requestTimeout = requestTimeout
    }

    private static func liveLoader(_ request: URLRequest) async throws -> MarketDataHTTPResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let expectedLength = response.expectedContentLength
        guard expectedLength <= Int64(maximumResponseBytes) else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(expectedLength)) }
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            data.append(byte)
        }
        return MarketDataHTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }

    private struct ChartResponse: Decodable {
        let chart: Chart
        struct Chart: Decodable {
            let result: [Result]?
        }
        struct Result: Decodable {
            let meta: Meta
            let indicators: Indicators
            let timestamp: [Int]?
        }
        struct Meta: Decodable {
            let regularMarketPrice: Double?
            let previousClose: Double?
            let chartPreviousClose: Double?
            let regularMarketTime: Int?
            let marketState: String?
            let exchangeDataDelayedBy: Int?
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
        request.timeoutInterval = 10
        request.setValue("https://finance.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("MarketMonitor/1.0", forHTTPHeaderField: "User-Agent")
        let response = try await load(request)
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Company names use a legacy encoding, while all price fields and separators are ASCII.
        let payload = String(decoding: response.data, as: UTF8.self)
        guard let quoteStart = payload.firstIndex(of: "\""),
            let quoteEnd = payload.lastIndex(of: "\""), quoteStart < quoteEnd
        else {
            throw URLError(.cannotParseResponse)
        }
        let fields = payload[payload.index(after: quoteStart)..<quoteEnd].split(
            separator: "~", omittingEmptySubsequences: false)
        guard fields.count > 30,
            let price = Double(fields[3]),
            let previous = Double(fields[4]),
            price.isFinite, previous.isFinite, price > 0, previous >= 0
        else {
            throw URLError(.cannotParseResponse)
        }
        let fetchedAt = now()
        guard let updatedAt = parseTencentTimestamp(fields[30], for: asset.symbol) else {
            throw URLError(.cannotParseResponse)
        }
        let change = price - previous
        return Quote(
            symbol: asset.symbol, displayName: asset.displayName, kind: asset.kind,
            price: price, change: change, changePercent: previous == 0 ? 0 : change / previous * 100,
            updatedAt: updatedAt, isDemo: false, isStale: false,
            marketState: tencentMarketState(for: asset.symbol, fetchedAt: fetchedAt, updatedAt: updatedAt))
    }

    private func fetchYahooQuote(for asset: Asset) async throws -> Quote {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(asset.symbol)")!
        components.queryItems = [
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "interval", value: "1m"),
            URLQueryItem(name: "includePrePost", value: "false"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue("MarketMonitor/1.0", forHTTPHeaderField: "User-Agent")
        let response = try await load(request)
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChartResponse.self, from: response.data)
        guard let result = decoded.chart.result?.first else { throw URLError(.cannotParseResponse) }

        guard let sample = latestYahooSample(from: result) else { throw URLError(.cannotParseResponse) }
        let price = sample.price
        let previous = result.meta.previousClose ?? result.meta.chartPreviousClose ?? price
        guard previous.isFinite, previous >= 0 else { throw URLError(.cannotParseResponse) }
        let updatedAt = Date(timeIntervalSince1970: TimeInterval(sample.timestamp))
        let fetchedAt = now()
        guard updatedAt <= fetchedAt.addingTimeInterval(300) else { throw URLError(.cannotParseResponse) }
        let change = price - previous
        return Quote(
            symbol: asset.symbol, displayName: asset.displayName, kind: asset.kind,
            price: price, change: change, changePercent: previous == 0 ? 0 : change / previous * 100,
            updatedAt: updatedAt, isDemo: false, isStale: false,
            marketState: yahooMarketState(
                result.meta.marketState,
                fetchedAt: fetchedAt,
                updatedAt: updatedAt),
            delayMinutes: result.meta.exchangeDataDelayedBy ?? 0)
    }

    private func latestYahooSample(from result: ChartResponse.Result) -> (price: Double, timestamp: Int)? {
        if let price = result.meta.regularMarketPrice,
            let timestamp = result.meta.regularMarketTime,
            price.isFinite, price > 0, timestamp > 0
        {
            return (price, timestamp)
        }

        guard let timestamps = result.timestamp,
            let closes = result.indicators.quote.first?.close,
            timestamps.count == closes.count
        else { return nil }
        for index in timestamps.indices.reversed() {
            guard let price = closes[index], price.isFinite, price > 0, timestamps[index] > 0 else { continue }
            return (price, timestamps[index])
        }
        return nil
    }

    private func load(_ request: URLRequest) async throws -> MarketDataHTTPResponse {
        let loader = loader
        let requestTimeout = requestTimeout
        return try await withThrowingTaskGroup(of: MarketDataHTTPResponse.self) { group in
            group.addTask { try await loader(request) }
            group.addTask {
                try await Task.sleep(for: requestTimeout)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else { throw URLError(.unknown) }
            guard response.data.count <= Self.maximumResponseBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            return response
        }
    }

    private func yahooMarketState(
        _ rawValue: String?,
        fetchedAt: Date,
        updatedAt: Date
    ) -> MarketSessionState {
        switch rawValue?.uppercased() {
        case "REGULAR":
            let age = fetchedAt.timeIntervalSince(updatedAt)
            return (-300...600).contains(age) ? .regular : .unknown
        case "PRE", "PREPRE": return .preMarket
        case "POST", "POSTPOST": return .postMarket
        case "CLOSED": return .closed
        default: return .unknown
        }
    }

    private func parseTencentTimestamp(_ value: Substring, for symbol: String) -> Date? {
        guard value.count == 14, value.allSatisfy(\.isNumber) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = marketTimeZone(for: symbol)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: String(value))
    }

    private func tencentMarketState(
        for symbol: String,
        fetchedAt: Date,
        updatedAt: Date
    ) -> MarketSessionState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = marketTimeZone(for: symbol)
        let weekday = calendar.component(.weekday, from: fetchedAt)
        guard (2...6).contains(weekday), calendar.isDate(fetchedAt, inSameDayAs: updatedAt) else {
            return .closed
        }

        let components = calendar.dateComponents([.hour, .minute], from: fetchedAt)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let sessions =
            symbol.hasSuffix(".HK")
            ? [570..<720, 780..<960]
            : [570..<690, 780..<900]
        guard sessions.contains(where: { $0.contains(minute) }) else { return .closed }

        let age = fetchedAt.timeIntervalSince(updatedAt)
        return (-300...600).contains(age) ? .regular : .unknown
    }

    private func marketTimeZone(for symbol: String) -> TimeZone {
        TimeZone(identifier: symbol.hasSuffix(".HK") ? "Asia/Hong_Kong" : "Asia/Shanghai")
            ?? TimeZone(secondsFromGMT: 8 * 3_600)!
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
