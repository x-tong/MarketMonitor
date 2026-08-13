import SwiftUI

struct MarketPopoverView: View {
    @EnvironmentObject private var store: MarketStore
    @State private var symbolInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            quoteList
            Divider()
            addRow
            footer
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Market Monitor")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(
                    store.lastRefresh.map {
                        "状态栏 · \(primaryDisplaySymbol) · \($0.formatted(date: .omitted, time: .shortened))"
                    } ?? "状态栏 · \(primaryDisplaySymbol)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(store.assets) { asset in
                    Button {
                        store.setPrimary(asset)
                    } label: {
                        if store.isPrimary(asset) {
                            Label(asset.displaySymbol, systemImage: "checkmark")
                        } else {
                            Text(asset.displaySymbol)
                        }
                    }
                }
            } label: {
                Label("状态栏：\(primaryDisplaySymbol)", systemImage: "menubar.rectangle")
            }
            .menuStyle(.borderlessButton)
            .help("选择状态栏显示的行情")
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 180 : 0))
                    .animation(.easeInOut(duration: 0.35), value: store.isRefreshing)
            }
            .buttonStyle(.borderless)
            .help("刷新行情")
            .disabled(store.isRefreshing)
        }
        .padding(16)
    }

    private var quoteList: some View {
        VStack(spacing: 0) {
            ForEach(store.assets) { asset in
                QuoteRow(asset: asset, quote: store.quotes[asset.symbol]) {
                    store.remove(asset)
                } onSetPrimary: {
                    store.setPrimary(asset)
                } isPrimary: {
                    store.isPrimary(asset)
                }
                if asset.id != store.assets.last?.id { Divider().padding(.leading, 62) }
            }
        }
        .padding(.vertical, 4)
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("添加代码，如 600519 / 0700.HK / BTC", text: $symbolInput)
                    .textFieldStyle(.plain)
                    .onSubmit(addAsset)
                    .disabled(store.isAdding)
                Button(action: addAsset) {
                    if store.isAdding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("添加")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minWidth: 48)
                .disabled(store.isAdding || symbolInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = store.addError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Label("腾讯行情 · Yahoo Finance", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func addAsset() {
        let submittedSymbol = symbolInput
        Task {
            if await store.add(symbol: submittedSymbol) {
                symbolInput = ""
            }
        }
    }

    private var primaryDisplaySymbol: String {
        store.assets.first(where: { $0.symbol == store.primarySymbol })?.displaySymbol ?? store.primarySymbol
    }
}

private struct QuoteRow: View {
    let asset: Asset
    let quote: Quote?
    let onRemove: () -> Void
    let onSetPrimary: () -> Void
    let isPrimary: () -> Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(asset.kind == .crypto ? Color.orange.opacity(0.16) : Color.blue.opacity(0.14))
                Image(systemName: asset.kind == .crypto ? "bitcoinsign" : "building.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(asset.kind == .crypto ? .orange : .blue)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.displaySymbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(asset.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(MarketFormatters.price(quote.price, kind: quote.kind))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(
                        "\(MarketFormatters.signed(quote.change, kind: quote.kind))  \(MarketFormatters.percent(quote.changePercent))"
                    )
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(quote.isPositive ? .green : .red)
                    Text(statusText(for: quote))
                        .font(.system(size: 9))
                        .foregroundStyle(statusColor(for: quote))
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Button(action: onSetPrimary) {
                Image(systemName: isPrimary() ? "pin.fill" : "pin")
                    .foregroundStyle(isPrimary() ? .blue : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isPrimary() ? "当前状态栏行情" : "设为状态栏行情")
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("移除 \(asset.symbol)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isPrimary() ? Color.accentColor.opacity(0.08) : .clear)
        .contextMenu {
            Button(isPrimary() ? "当前状态栏行情" : "设为状态栏行情", action: onSetPrimary)
                .disabled(isPrimary())
            Button("移除") { onRemove() }
        }
    }

    private func statusText(for quote: Quote) -> String {
        let time = quote.updatedAt.formatted(date: .omitted, time: .shortened)
        if quote.isDemo && quote.isStale { return "模拟 · 已过期 · \(time)" }
        if quote.isDemo { return "模拟 · \(time)" }
        if quote.isStale { return "已过期 · \(time)" }
        return "更新于 \(time)"
    }

    private func statusColor(for quote: Quote) -> Color {
        quote.isDemo || quote.isStale ? .orange : .secondary
    }
}
