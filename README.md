# MarketMonitor

MarketMonitor is a lightweight macOS menu bar app for watching stocks and cryptocurrencies. It supports US stocks, mainland China A-shares, Hong Kong stocks, and common USD crypto pairs.

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

This project is currently an alpha suitable for local evaluation. The public endpoints can rate-limit or change without notice. The generated bundle is a local debug artifact; it is not Developer ID signed, hardened, notarized, or ready for public distribution.

## Repository Layout

```text
App/       SwiftUI app source
Tests/     deterministic unit tests
script/    build, run, and validation commands
dist/      generated local app bundle (ignored)
```
