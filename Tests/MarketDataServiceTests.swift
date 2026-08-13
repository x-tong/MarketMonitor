import Foundation
import Testing

@testable import MarketMonitor

@Suite("Market data service")
struct MarketDataServiceTests {
    @Test("Parses Yahoo quote fields")
    func parsesYahooQuote() async throws {
        let quoteDate = Date(timeIntervalSince1970: 1_000)
        let payload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {"regularMarketPrice": 123.5, "previousClose": 120.0},
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
            now: { quoteDate })

        let quote = try await service.fetchQuote(for: Asset(symbol: "AAPL", displayName: "Apple", kind: .stock))

        #expect(quote.price == 123.5)
        #expect(quote.change == 3.5)
        #expect(quote.changePercent == 3.5 / 120.0 * 100)
        #expect(quote.updatedAt == quoteDate)
        #expect(!quote.isDemo)
        #expect(!quote.isStale)
    }

    @Test("Parses Tencent quote fields")
    func parsesTencentQuote() async throws {
        let payload = Data(#"v_sh600519="1~name~600519~150.50~149.00";"#.utf8)
        let service = MarketDataService { request in
            #expect(request.url?.absoluteString == "https://qt.gtimg.cn/q=sh600519")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://finance.qq.com/")
            return MarketDataHTTPResponse(data: payload, statusCode: 200)
        }

        let asset = Asset(symbol: "600519.SS", displayName: "贵州茅台", kind: .stock)
        let quote = try await service.fetchQuote(for: asset)

        #expect(quote.price == 150.5)
        #expect(quote.change == 1.5)
        #expect(quote.changePercent == 1.5 / 149.0 * 100)
        #expect(!quote.isDemo)
        #expect(!quote.isStale)
    }

    @Test("Falls back from Tencent to Yahoo")
    func fallsBackToYahoo() async throws {
        let requests = RequestRecorder()
        let yahooPayload = Data(
            """
            {
              "chart": {
                "result": [{
                  "meta": {"regularMarketPrice": 150.0, "previousClose": 145.0},
                  "indicators": {"quote": [{"close": [150.0]}]}
                }]
              }
            }
            """.utf8)
        let service = MarketDataService { request in
            await requests.record(request.url)
            if request.url?.host == "qt.gtimg.cn" {
                return MarketDataHTTPResponse(data: Data(), statusCode: 503)
            }
            return MarketDataHTTPResponse(data: yahooPayload, statusCode: 200)
        }

        let asset = Asset(symbol: "600519.SS", displayName: "贵州茅台", kind: .stock)
        let quote = try await service.fetchQuote(for: asset)
        let requestedURLs = await requests.urls

        #expect(quote.price == 150.0)
        #expect(requestedURLs.count == 2)
        #expect(requestedURLs.first?.absoluteString == "https://qt.gtimg.cn/q=sh600519")
        #expect(requestedURLs.last?.path.hasSuffix("/600519.SS") == true)
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

private actor RequestRecorder {
    private(set) var urls: [URL] = []

    func record(_ url: URL?) {
        if let url { urls.append(url) }
    }
}
