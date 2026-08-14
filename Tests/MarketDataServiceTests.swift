import Foundation
import Testing

@testable import MarketMonitor

@Suite("Market data service")
struct MarketDataServiceTests {
    @Test("Parses Yahoo quote fields")
    func parsesYahooQuote() async throws {
        let quoteDate = Date(timeIntervalSince1970: 1_000)
        let fetchDate = Date(timeIntervalSince1970: 1_030)
        let payload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {
                    "regularMarketPrice": 123.5,
                    "previousClose": 120.0,
                    "regularMarketTime": 1000,
                    "marketState": "REGULAR",
                    "exchangeDataDelayedBy": 0
                  },
                  "indicators": {"quote": [{"close": [null, 123.5]}]}
                }]
              }
            }
            """.utf8)
        let service = MarketDataService(
            loader: { request in
                #expect(request.url?.host == "query1.finance.yahoo.com")
                return MarketDataHTTPResponse(data: payload, statusCode: 200)
            },
            now: { fetchDate })

        let quote = try await service.fetchQuote(for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))

        #expect(quote.price == 123.5)
        #expect(quote.change == 3.5)
        #expect(quote.changePercent == 3.5 / 120.0 * 100)
        #expect(quote.updatedAt == quoteDate)
        #expect(quote.marketState == .regular)
        #expect(!quote.isDelayed)
        #expect(!quote.isDemo)
        #expect(!quote.isStale)
    }

    @Test("Parses Tencent quote fields")
    func parsesTencentQuote() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let quoteDate = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 10, minute: 0)))
        let fetchDate = quoteDate.addingTimeInterval(30)
        let payload = tencentPayload(timestamp: "20260814100000")
        let service = MarketDataService(
            loader: { request in
                #expect(request.url?.absoluteString == "https://qt.gtimg.cn/q=sh600519")
                #expect(request.value(forHTTPHeaderField: "Referer") == "https://finance.qq.com/")
                #expect(request.timeoutInterval == 10)
                return MarketDataHTTPResponse(data: payload, statusCode: 200)
            },
            now: { fetchDate })

        let asset = Asset(symbol: "600519.SS", displayName: "贵州茅台", kind: .stock)
        let quote = try await service.fetchQuote(for: asset)

        #expect(quote.price == 150.5)
        #expect(quote.change == 1.5)
        #expect(quote.changePercent == 1.5 / 149.0 * 100)
        #expect(quote.updatedAt == quoteDate)
        #expect(quote.marketState == .regular)
        #expect(!quote.isDemo)
        #expect(!quote.isStale)
    }

    @Test("Falls back from Tencent to Yahoo")
    func fallsBackToYahoo() async throws {
        let requests = RequestRecorder()
        let fetchDate = Date(timeIntervalSince1970: 2_000)
        let yahooPayload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {
                    "regularMarketPrice": 150.0,
                    "previousClose": 145.0,
                    "regularMarketTime": 1000,
                    "marketState": "CLOSED"
                  },
                  "indicators": {"quote": [{"close": [150.0]}]}
                }]
              }
            }
            """.utf8)
        let service = MarketDataService(
            loader: { request in
                await requests.record(request.url)
                if request.url?.host == "qt.gtimg.cn" {
                    return MarketDataHTTPResponse(data: Data(), statusCode: 503)
                }
                return MarketDataHTTPResponse(data: yahooPayload, statusCode: 200)
            },
            now: { fetchDate })

        let asset = Asset(symbol: "600519.SS", displayName: "贵州茅台", kind: .stock)
        let quote = try await service.fetchQuote(for: asset)
        let requestedURLs = await requests.urls

        #expect(quote.price == 150.0)
        #expect(requestedURLs.count == 2)
        #expect(requestedURLs.first?.absoluteString == "https://qt.gtimg.cn/q=sh600519")
        #expect(requestedURLs.last?.path.hasSuffix("/600519.SS") == true)
        #expect(quote.marketState == .closed)
    }

    @Test("Preserves closed and delayed Yahoo status")
    func preservesClosedDelayedStatus() async throws {
        let payload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {
                    "regularMarketPrice": 123.5,
                    "previousClose": 120.0,
                    "regularMarketTime": 1000,
                    "marketState": "CLOSED",
                    "exchangeDataDelayedBy": 15
                  },
                  "indicators": {"quote": [{"close": [123.5]}]}
                }]
              }
            }
            """.utf8)
        let service = MarketDataService(
            loader: { _ in MarketDataHTTPResponse(data: payload, statusCode: 200) },
            now: { Date(timeIntervalSince1970: 2_000) })

        let quote = try await service.fetchQuote(
            for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))

        #expect(quote.updatedAt == Date(timeIntervalSince1970: 1_000))
        #expect(quote.marketState == .closed)
        #expect(quote.delayMinutes == 15)
        #expect(!quote.isAlertEligible)
    }

    @Test("Pairs fallback Yahoo closes with their matching timestamps")
    func pairsFallbackYahooSamples() async throws {
        let payload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {"previousClose": 120.0, "marketState": "REGULAR"},
                  "timestamp": [1000, 2000],
                  "indicators": {"quote": [{"close": [123.5, null]}]}
                }]
              }
            }
            """.utf8)
        let service = MarketDataService(
            loader: { _ in MarketDataHTTPResponse(data: payload, statusCode: 200) },
            now: { Date(timeIntervalSince1970: 2_030) })

        let quote = try await service.fetchQuote(
            for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))

        #expect(quote.price == 123.5)
        #expect(quote.updatedAt == Date(timeIntervalSince1970: 1_000))
        #expect(quote.marketState == .unknown)
        #expect(!quote.isAlertEligible)
    }

    @Test("Rejects mismatched Yahoo timestamp and close arrays")
    func rejectsMismatchedYahooSamples() async {
        let payload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {"previousClose": 120.0, "marketState": "REGULAR"},
                  "timestamp": [1000, 2000],
                  "indicators": {"quote": [{"close": [123.5]}]}
                }]
              }
            }
            """.utf8)
        let service = MarketDataService(
            loader: { _ in MarketDataHTTPResponse(data: payload, statusCode: 200) },
            now: { Date(timeIntervalSince1970: 2_030) })

        await #expect(throws: (any Error).self) {
            try await service.fetchQuote(
                for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))
        }
    }

    @Test("Times out an unresponsive provider")
    func timesOutUnresponsiveProvider() async {
        let service = MarketDataService(
            loader: { _ in
                try await Task.sleep(for: .seconds(1))
                return MarketDataHTTPResponse(data: Data(), statusCode: 200)
            },
            requestTimeout: .milliseconds(10))

        do {
            _ = try await service.fetchQuote(
                for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))
            Issue.record("Expected the provider request to time out")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Expected URLError.timedOut, received \(error)")
        }
    }

    @Test("Rejects provider responses beyond the byte limit")
    func rejectsOversizedResponse() async {
        let service = MarketDataService { _ in
            MarketDataHTTPResponse(
                data: Data(count: MarketDataService.maximumResponseBytes + 1),
                statusCode: 200)
        }

        do {
            _ = try await service.fetchQuote(
                for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))
            Issue.record("Expected the oversized response to be rejected")
        } catch let error as URLError {
            #expect(error.code == .dataLengthExceedsMaximum)
        } catch {
            Issue.record("Expected URLError.dataLengthExceedsMaximum, received \(error)")
        }
    }

    @Test("Rejects invalid provider prices")
    func rejectsInvalidPrice() async {
        let payload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {"regularMarketPrice": 0.0, "previousClose": 120.0},
                  "indicators": {"quote": [{"close": [0.0]}]}
                }]
              }
            }
            """.utf8)
        let service = MarketDataService { _ in
            MarketDataHTTPResponse(data: payload, statusCode: 200)
        }

        await #expect(throws: (any Error).self) {
            try await service.fetchQuote(for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))
        }
    }
}

private func tencentPayload(timestamp: String) -> Data {
    var fields = Array(repeating: "", count: 31)
    fields[0] = "1"
    fields[1] = "name"
    fields[2] = "600519"
    fields[3] = "150.50"
    fields[4] = "149.00"
    fields[30] = timestamp
    return Data("v_sh600519=\"\(fields.joined(separator: "~"))\";".utf8)
}

private actor RequestRecorder {
    private(set) var urls: [URL] = []

    func record(_ url: URL?) {
        if let url { urls.append(url) }
    }
}
