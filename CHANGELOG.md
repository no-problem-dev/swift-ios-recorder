# Changelog

## [Unreleased]

### Changed

- Raised the swift-design-system pin to 4.0.0.

## [0.7.0] - 2026-08-11

### Changed

- Every label `iOSRecorderUI` draws is in English. These strings render inside the host app, so a
  developer adopting this package was shipping Japanese into their own debug console without ever
  seeing it. That includes the default `title` of the `DebugSection` factories
  (`.metrics`, `.timeline`, `.captures`, `.maintenance`, `.designSystemCatalog`), which are default
  argument values a caller can still override with anything.
- `MetricsReport(title:series:axes:)` names its single implicit scope `"Total"` rather than `"合計"`.
  That label is the scope's `Identifiable` id, but it is view identity only — `MetricsReport` and
  `MetricsScope` are not `Codable` and are never persisted, so nothing encoded changes.
- Artifact-kind chips and section headings still derive their text from `ArtifactKind.rawValue`; the
  raw values themselves (`screenshot`, `state`, `log`, `network`, `debug_timeline`, `metrics`) are
  what gets encoded and sent to the Mac, and they are untouched.

## [0.6.0] - 2026-08-11

### Changed

- Raised the swift-structured-data pin to 3.0.0. That release makes the YAML parser reject
  constructs it does not model instead of silently dropping them; nothing in this package's own
  API changes.


## [0.5.0] - 2026-07-19

### Changed

- Raised the swift-design-system pin to 2.0.1, keeping the package family on one generation.

## [0.4.1] - 2026-07-19

### Added

- DocC documentation for all seven modules, published to GitHub Pages as one combined site
  with `iOSRecorder` as the entry point.
- An installation section in the README, pointing at a released tag.
- LICENSE and the standard CI workflows.

### Changed

- Doc comments and DocC pages rewritten for quality; the README split into English and Japanese.
- Internal helpers that had been left public were reduced to internal visibility. Anything you
  were able to reach before but cannot now was never meant to be part of the API.

## [0.4.0] - 2026-06-07

### Added

- Shake to toggle the recorder, so a capture can be taken without hunting for the floating button.

### Changed

- Reorganised the controls in the debug panel.

## [0.3.1] - 2026-06-07

### Changed

- The debug UI now renders compact by default and expands on demand, so a long capture list stays
  readable on a phone.

## [0.3.0] - 2026-06-07

### Fixed

- Capped capture size at the point of writing rather than at the point of reading. Oversized
  payloads were previously stored and only rejected later, which wasted device storage and made
  the failure surface far from its cause.

## [0.2.0] - 2026-06-06

### Added

- `search_events` and `get_event`, so an agent can find one debug event across many captures
  instead of pulling whole captures to look inside them. The search result states how many
  records were scanned and whether it was truncated, so "not found" can be told apart from
  "stopped looking".

## [0.1.0] - 2026-06-06

First release. Captures the screen and state of an iOS app under development and hands them to
an AI agent over MCP.

### Added

- Core recording: sources, capture sessions, ring-buffer storage, and the export path.
- Screenshot, state, log, network and metrics sources.
- SwiftUI integration: floating button, in-app viewer, and a declarative debug console.
- Bonjour transfer to a Mac, and a file-backed store on the Mac side.
- An MCP server exposing captures to an agent, with images downscaled before they are returned.
- Response bodies that are not text, and timeline payloads, are dropped at capture time rather
  than at read time, so secrets and bulk never reach storage.
