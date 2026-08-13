import Foundation

struct Asset: Identifiable, Codable, Hashable {
    let symbol: String
    let displayName: String
    let kind: AssetKind

    var id: String { symbol }
    var displaySymbol: String {
        symbol.replacingOccurrences(of: "-USD", with: "")
    }

    enum AssetKind: String, Codable {
        case stock
        case crypto
    }

    static let defaults: [Asset] = [
        Asset(symbol: "AAPL", displayName: "Apple", kind: .stock),
        Asset(symbol: "NVDA", displayName: "NVIDIA", kind: .stock),
        Asset(symbol: "BTC-USD", displayName: "Bitcoin", kind: .crypto),
        Asset(symbol: "ETH-USD", displayName: "Ethereum", kind: .crypto),
    ]

    static func from(symbol rawSymbol: String) -> Asset? {
        let input =
            rawSymbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard !input.isEmpty else { return nil }

        let normalized = normalizedSymbol(from: input)
        let isCrypto = normalized.hasSuffix("-USD")
        let knownNames: [String: String] = [
            "AAPL": "Apple", "NVDA": "NVIDIA", "MSFT": "Microsoft", "TSLA": "Tesla",
            "AMZN": "Amazon", "GOOGL": "Alphabet", "META": "Meta", "BTC-USD": "Bitcoin",
            "ETH-USD": "Ethereum", "SOL-USD": "Solana", "DOGE-USD": "Dogecoin",
            "600519.SS": "贵州茅台", "601318.SS": "中国平安", "000001.SZ": "平安银行",
            "300750.SZ": "宁德时代", "0700.HK": "腾讯控股", "9988.HK": "阿里巴巴-W",
            "1211.HK": "比亚迪股份",
        ]
        return Asset(
            symbol: normalized, displayName: knownNames[normalized] ?? normalized, kind: isCrypto ? .crypto : .stock)
    }

    private static func normalizedSymbol(from input: String) -> String {
        let cryptoSymbols = ["BTC", "ETH", "SOL", "DOGE"]
        if cryptoSymbols.contains(input) { return "\(input)-USD" }

        if input.hasSuffix(".SH") {
            return String(input.dropLast(3)) + ".SS"
        }
        if input.hasSuffix(".SS") || input.hasSuffix(".SZ") || input.hasSuffix(".BJ") {
            return input
        }
        if input.hasSuffix(".HK") {
            return normalizedHongKongCode(String(input.dropLast(3))) ?? input
        }

        for prefix in ["SH:", "SSE:", "SH", "SSE"] where input.hasPrefix(prefix) {
            let code = String(input.dropFirst(prefix.count))
            if isDigits(code), code.count == 6 { return "\(code).SS" }
        }
        for prefix in ["SZ:", "SZSE:", "SZ", "SZSE"] where input.hasPrefix(prefix) {
            let code = String(input.dropFirst(prefix.count))
            if isDigits(code), code.count == 6 { return "\(code).SZ" }
        }
        for prefix in ["BJ:", "BSE:", "BJ", "BSE"] where input.hasPrefix(prefix) {
            let code = String(input.dropFirst(prefix.count))
            if isDigits(code), code.count == 6 { return "\(code).BJ" }
        }
        for prefix in ["HK:", "HKEX:", "HK", "HKEX"] where input.hasPrefix(prefix) {
            let code = String(input.dropFirst(prefix.count))
            if let normalized = normalizedHongKongCode(code) { return normalized }
        }

        if isDigits(input), input.count == 6 {
            if input.hasPrefix("4") || input.hasPrefix("8") { return input + ".BJ" }
            let shanghaiPrefixes = ["5", "6", "9"]
            let suffix = shanghaiPrefixes.contains(where: input.hasPrefix) ? ".SS" : ".SZ"
            return input + suffix
        }
        if isDigits(input), (1...5).contains(input.count) {
            return normalizedHongKongCode(input) ?? input
        }
        return input
    }

    private static func normalizedHongKongCode(_ code: String) -> String? {
        guard isDigits(code), (1...5).contains(code.count) else { return nil }
        let canonical = String(code.drop(while: { $0 == "0" }))
        guard !canonical.isEmpty, canonical.count <= 4 else { return nil }
        return String(repeating: "0", count: 4 - canonical.count) + canonical + ".HK"
    }

    private static func isDigits(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }
}
