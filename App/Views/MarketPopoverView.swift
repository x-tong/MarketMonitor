import SwiftUI

struct MarketPopoverView: View {
    @EnvironmentObject private var store: MarketStore
    @State private var symbolInput = ""
    @State private var alertAssetSymbol = ""
    @State private var alertCondition: AlertRule.Condition = .priceAbove
    @State private var alertThreshold = ""
    @State private var alertCooldownMinutes = "60"
    @State private var quietStart = "22:00"
    @State private var quietEnd = "07:00"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            quoteList
            Divider()
            alertsSection
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

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("价格提醒", systemImage: "bell.badge")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(
                    "暂停",
                    isOn: Binding(
                        get: { store.monitoringPaused },
                        set: { store.setMonitoringPaused($0) })
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(store.monitoringPaused ? "恢复提醒" : "暂停所有提醒")
            }
            if store.monitoringPaused {
                Text("提醒已暂停")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !store.alertRules.isEmpty {
                VStack(spacing: 0) {
                    ForEach(store.alertRules) { rule in
                        alertRuleRow(rule)
                        if rule.id != store.alertRules.last?.id { Divider().padding(.leading, 28) }
                    }
                }
            }
            addAlertRuleRow
            quietHoursRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .task {
            if alertAssetSymbol.isEmpty { alertAssetSymbol = store.assets.first?.symbol ?? "" }
        }
    }

    private func alertRuleRow(_ rule: AlertRule) -> some View {
        HStack(spacing: 8) {
            Toggle(
                "",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { store.setAlertRuleEnabled(rule, isEnabled: $0) })
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(displaySymbol(for: rule.assetSymbol)) · \(rule.condition.title) \(thresholdText(for: rule))")
                    .font(.caption)
                    .lineLimit(1)
                Text(lastTriggerText(for: rule))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                store.removeAlertRule(rule)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("删除提醒")
        }
        .padding(.vertical, 4)
    }

    private var addAlertRuleRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(store.assets) { asset in
                    Button {
                        alertAssetSymbol = asset.symbol
                    } label: {
                        if alertAssetSymbol == asset.symbol {
                            Label(asset.displaySymbol, systemImage: "checkmark")
                        } else {
                            Text(asset.displaySymbol)
                        }
                    }
                }
            } label: {
                Text(displaySymbol(for: alertAssetSymbol))
                    .frame(minWidth: 48, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            Menu {
                ForEach(AlertRule.Condition.allCases, id: \.self) { condition in
                    Button {
                        alertCondition = condition
                    } label: {
                        if alertCondition == condition {
                            Label(condition.title, systemImage: "checkmark")
                        } else {
                            Text(condition.title)
                        }
                    }
                }
            } label: {
                Text(alertCondition.title)
                    .frame(minWidth: 58, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            TextField("阈值", text: $alertThreshold)
                .textFieldStyle(.roundedBorder)
                .frame(width: 62)
            TextField("分钟", text: $alertCooldownMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
            Button {
                addAlertRule()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("添加提醒")
            .disabled(alertAssetSymbol.isEmpty || Double(alertThreshold) == nil || Double(alertCooldownMinutes) == nil)
        }
    }

    private var quietHoursRow: some View {
        HStack(spacing: 6) {
            Toggle(
                "静默时段",
                isOn: Binding(
                    get: { store.quietHoursEnabled },
                    set: { updateQuietHours(enabled: $0) })
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
            TextField("22:00", text: $quietStart)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
            Text("-")
                .foregroundStyle(.secondary)
            TextField("07:00", text: $quietEnd)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
            Button {
                updateQuietHours(enabled: store.quietHoursEnabled)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .help("保存静默时段")
        }
        .font(.caption)
        .onAppear {
            quietStart = minuteText(store.quietHoursStartMinute)
            quietEnd = minuteText(store.quietHoursEndMinute)
        }
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

    private func addAlertRule() {
        guard let threshold = Double(alertThreshold), let cooldown = Double(alertCooldownMinutes),
            let asset = store.assets.first(where: { $0.symbol == alertAssetSymbol })
        else { return }
        if store.addAlertRule(
            asset: asset,
            condition: alertCondition,
            threshold: threshold,
            cooldown: cooldown * 60)
        {
            alertThreshold = ""
        }
    }

    private func updateQuietHours(enabled: Bool) {
        store.setQuietHours(
            enabled: enabled,
            startMinute: parseMinute(quietStart) ?? store.quietHoursStartMinute,
            endMinute: parseMinute(quietEnd) ?? store.quietHoursEndMinute)
    }

    private func displaySymbol(for symbol: String) -> String {
        store.assets.first(where: { $0.symbol == symbol })?.displaySymbol ?? (symbol.isEmpty ? "代码" : symbol)
    }

    private func thresholdText(for rule: AlertRule) -> String {
        rule.condition.isPercentage
            ? MarketFormatters.percent(rule.threshold)
            : MarketFormatters.price(
                rule.threshold, kind: store.assets.first(where: { $0.symbol == rule.assetSymbol })?.kind ?? .stock)
    }

    private func lastTriggerText(for rule: AlertRule) -> String {
        guard let date = rule.lastTriggeredAt, let price = rule.lastTriggeredPrice,
            let asset = store.assets.first(where: { $0.symbol == rule.assetSymbol })
        else { return "等待触发" }
        return
            "上次 \(MarketFormatters.price(price, kind: asset.kind)) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func minuteText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func parseMinute(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
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
