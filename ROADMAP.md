# MarketMonitor Roadmap

## Product Direction

MarketMonitor is a personal, open-source macOS utility for people who want to follow a small watchlist at work
without keeping a brokerage or charting application open.

The product should help users look at markets less often, not encourage continuous monitoring. It should remain a
small menu-bar-only application that is private by default, honest about data quality, and inexpensive to maintain.

## Product Principles

- Trust before breadth: never present demo, stale, delayed, or closed-market data as live data.
- Event-driven attention: notify users when a configured condition matters instead of adding more dashboards.
- Local by default: keep watchlists, rules, and preferences on the Mac without requiring an account.
- Low interruption: support quiet hours, cooldowns, and a quick way to pause monitoring.
- Small dependency surface: prefer Apple frameworks and simple provider boundaries that can be tested offline.
- Cross-market consistency: use the same small set of concepts for US, mainland China, Hong Kong, and crypto assets.

## Milestones

### v0.2 - Reliable Alerts

Goal: turn the current quote viewer into a useful, low-interruption market sentinel.

- Add per-asset price-above, price-below, and percentage-change alert rules.
- Trigger notifications only from validated, non-demo, non-stale quotes.
- Add per-rule cooldowns and prevent repeated notifications while a condition remains true.
- Add quiet hours and a global pause control.
- Show the last trigger price and time for each rule.
- Persist alert rules locally and cover evaluation, cooldown, and persistence with deterministic tests.

Definition of done:

- A user can configure an alert, close the popover, and receive at most one notification per cooldown period.
- Demo, stale, malformed, or failed quote updates cannot trigger an alert.
- Quiet hours and pause state survive application restarts.
- `./script/check.sh` and application launch verification pass.

### v0.3 - Dependable Daily Use

Goal: make the application reliable enough to remain running throughout a normal workday.

- Detect market sessions and reduce unnecessary polling outside trading hours.
- Refresh immediately after network recovery and macOS wake without creating overlapping refresh tasks.
- Distinguish live, delayed, closed, and stale states when providers expose enough information.
- Add provider health diagnostics without exposing credentials or watchlist data.
- Add JSON import and export for watchlists and alert rules.
- Exercise a two-week self-use checklist and record failures as reproducible issues.

Definition of done:

- Sleep, wake, offline, and reconnect scenarios recover without restarting the app.
- Provider failures remain visible and never replace trustworthy quotes with fabricated values.
- A user can back up and restore all local configuration.
- No known high-severity data-trust or duplicate-notification defects remain.

### v1.0 - Open-Source Ready

Goal: make installation, contribution, and maintenance practical for users beyond the original author.

- Choose and add an open-source license.
- Add contribution guidelines, issue templates, and a code of conduct.
- Document privacy behavior, data sources, provider limitations, and notification permissions.
- Add semantic versioning and a changelog.
- Produce reproducible release builds and document signing and notarization.
- Test the documented install and upgrade paths on the oldest supported macOS version.

Definition of done:

- A new contributor can build, test, and understand the provider/store boundaries from repository documentation.
- A user can install a versioned build without bypassing normal macOS security protections.
- CI validates all deterministic tests on supported toolchains.
- Release notes clearly state data-source limitations and breaking preference changes.

## Explicit Non-Goals

- Brokerage login, account synchronization, or order execution.
- A full charting terminal, technical-indicator library, or news feed.
- Social features, stock recommendations, or automated trading advice.
- Hiding the application from employer device management or bypassing workplace policies.
- Exchange-grade real-time guarantees from unsupported public endpoints.
- Supporting many providers unless an existing provider is unreliable or a market cannot otherwise be covered.

## Prioritization Rule

When choosing work, prefer the smallest change that improves one of these outcomes:

1. Users can trust the displayed state.
2. Users need to check prices less often.
3. The app recovers from normal desktop lifecycle events.
4. A contributor can change the app without requiring live endpoints.

Features that do not materially improve one of these outcomes should remain outside the roadmap.
