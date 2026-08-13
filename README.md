# MarketMonitor

MarketMonitor is a lightweight macOS menu bar app for watching stocks and cryptocurrencies. It supports US stocks, mainland China A-shares, Hong Kong stocks, and common USD crypto pairs.

It is designed as a personal, open-source utility for checking a small watchlist at work without keeping a full
brokerage application open. The project prioritizes trustworthy quote state, low-interruption alerts, local data,
and low maintenance cost over trading, charting, or news features. See [ROADMAP.md](ROADMAP.md) for milestones and
explicit non-goals.

## Requirements

- macOS 13 or newer
- Apple Swift 6 toolchain
- Internet access for live quotes

## Run

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM executable, stages `dist/MarketMonitor.app`, stops an older running instance, and opens the new app bundle. The app intentionally runs without a Dock icon.

Useful variants:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

## Install A Release

GitHub Releases provide a `.dmg` and `.zip` built for Apple Silicon (`arm64`). The
release artifacts are not Developer ID signed or notarized, so
macOS may show a security warning the first time the app is opened.

1. Download the `.dmg` from the repository's Releases page.
2. Open it and drag `MarketMonitor.app` to `Applications`.
3. On the first launch, Control-click the app in Finder and choose **Open**, then confirm **Open**.
4. If macOS still blocks it, open **System Settings > Privacy & Security**, find the blocked app message, and choose **Open Anyway**.

The app is menu-bar-only and will not appear in the Dock. The current release requires
an Apple Silicon Mac running macOS 13 or newer and internet access for live quotes. The
first alert trigger asks for notification permission.

Maintainers can build the same artifacts locally with:

```bash
./script/package_release.sh 0.2.0
```

The script writes ignored artifacts to `dist/releases/` and intentionally uses an
ad-hoc signature. This is a low-cost distribution path for a personal open-source
project; it does not provide the trust guarantees of Developer ID signing and notarization.

## Development

Run the repository quality gate before committing:

```bash
./script/check.sh
```

This checks formatting, runs deterministic tests, and builds the app. Repository conventions and architectural constraints are documented in `AGENTS.md`.

Run tests alone with `./script/test.sh`. The wrapper uses ordinary `swift test` with a full Xcode installation and supplies the missing Swift Testing search paths when only Apple Command Line Tools are selected.

## Symbols

Examples accepted by the add field:

| Market | Examples |
| --- | --- |
| US stocks | `AAPL`, `NVDA` |
| Shanghai | `600519`, `600519.SS`, `600519.SH`, `SH:600519` |
| Shenzhen | `000001`, `000001.SZ`, `SZ:000001` |
| Beijing | `430047`, `430047.BJ`, `BJ:430047` |
| Hong Kong | `700.HK`, `0700.HK`, `HK:700` |
| Crypto | `BTC`, `ETH`, `SOL` |

Six-digit mainland codes are inferred from their leading digit. Use an explicit market suffix when a code is ambiguous.

## Data Sources And Status

- A-share and Hong Kong quotes prefer Tencent's public quote endpoint and fall back to Yahoo Finance.
- US stock and cryptocurrency quotes use Yahoo Finance.
- Quotes refresh every 30 seconds. This is polling, not an exchange-grade real-time feed.
- Demo and stale quotes are labeled in both the menu bar and quote list. A failed refresh preserves the
  previous quote and timestamp, and marks that quote as stale.
- New symbols are saved only after a market-data provider returns a valid live quote.
- Price and percentage alerts support per-rule cooldowns, condition re-arming, quiet hours, and a persisted global pause.
  Notifications are emitted only from validated, non-demo, non-stale quotes after macOS notification permission is granted.

This project is currently an alpha suitable for local evaluation and informal release testing. The public endpoints can rate-limit or change without notice. Release artifacts are ad-hoc signed and not notarized.

## Repository Layout

```text
App/       SwiftUI app source
Tests/     deterministic unit tests
script/    build, run, and validation commands
dist/      generated local app bundle (ignored)
```
