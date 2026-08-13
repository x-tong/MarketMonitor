# MarketMonitor Agent Guide

## Project Purpose

MarketMonitor is a menu-bar-only macOS app that displays stock and cryptocurrency quotes. It is a SwiftPM GUI executable targeting macOS 13 or newer.

## Repository Map

- `App/MarketMonitorApp.swift`: app entry point and menu bar scene.
- `App/Models/`: persisted assets and in-memory quote values.
- `App/Services/`: external market-data clients and response parsing.
- `App/Stores/`: main-actor application state, refresh scheduling, and persistence.
- `App/Views/`: SwiftUI menu bar label and popover UI.
- `App/Support/`: pure formatting helpers.
- `Tests/`: deterministic unit tests. Tests must not depend on live market APIs.
- `script/build_and_run.sh`: canonical local build, bundle, and launch command.
- `script/test.sh`: canonical test command, including Command Line Tools compatibility.
- `script/check.sh`: canonical non-interactive quality gate.

## Required Commands

- Build: `swift build`
- Test: `./script/test.sh`
- Format check: `swift format lint --recursive App Tests Package.swift`
- Full validation: `./script/check.sh`
- Build and launch: `./script/build_and_run.sh`
- Build and verify process launch: `./script/build_and_run.sh --verify`

Run `./script/check.sh` before declaring a code change complete. For UI or app-lifecycle changes, also run `./script/build_and_run.sh --verify` on macOS.

## Engineering Constraints

- Keep the app menu-bar-only unless the product requirement explicitly changes. The `.accessory` activation policy is intentional.
- Keep app-wide mutable state in `MarketStore`, which is isolated to `@MainActor`.
- Keep HTTP and provider-specific parsing in `MarketDataService`; views must not make network requests.
- Treat provider responses as untrusted. Validate status codes, field counts, numeric values, and missing data.
- Do not persist an asset until its symbol has been normalized and, when the flow supports it, validated by a provider.
- Never present demo or stale data as live data. Preserve and surface `Quote.isDemo` and timestamps when changing quote state.
- A-share and Hong Kong quotes prefer Tencent with Yahoo fallback. US stocks and crypto use Yahoo. Do not silently change symbol or field mappings without focused tests.
- Keep tests deterministic. Put live endpoint checks in explicit diagnostic scripts, not the default test suite.
- Preserve macOS 13 compatibility; guard newer SwiftUI APIs with availability checks.
- Use semantic system colors and materials so the UI follows Light and Dark appearances.
- Add dependencies only when the standard library and Apple frameworks are insufficient, and document the reason in the change.
- Commit `Package.resolved` when SwiftPM creates it so application dependency versions remain reproducible.

## Style

- Use four-space indentation and run `swift format` with the repository configuration.
- Prefer small, responsibility-based files over a monolithic view or store.
- Use ASCII for identifiers and comments. User-facing Chinese copy is expected and may use Unicode.
- Comments should explain provider quirks, lifecycle constraints, or non-obvious invariants.

## Completion Checklist

1. Relevant behavior has focused tests where it can be tested deterministically.
2. `./script/check.sh` passes.
3. UI or lifecycle changes are launch-verified through the project script.
4. No build output, local preferences, credentials, or generated app bundles are committed.
5. User-facing limitations and setup changes are reflected in `README.md`.
