# RTT development plan

## Scope and decisions

- Targets: Android, Windows, macOS, and Linux from one Flutter project.
- Local-first: every feature works against a local SQLite 3 database.
- Online mode: optional HTTPS sync to PHP 8 + SQLite on cPanel; no accounts, teams, or multi-user UI.
- Baseline features: projects, one running timer, manual/editable entries, history filters, summaries/reports, CSV export, backups, and desktop tray controls.
- Defer Baralga compatibility import, Excel/iCalendar export, undo/redo, and charts until the baseline is proven.

## Repository layout

```text
app/             Flutter application (created after plan approval)
server/          framework-free PHP 8 sync API
  public/        deployable HTTP entry points
  sql/           server database schema and migrations
contracts/       versioned JSON request/response contracts
docs/            research, architecture, decisions, and operations notes
scripts/         repeatable build/package helpers
SHARE/           final standalone Git repository and release artifacts
```

## Delivery phases

1. Bootstrap Flutter with Android and desktop targets; add linting, formatting, a minimal test, and the SQLite database migration runner.
2. Build local-first core: project CRUD, a single persisted running entry, manual entries, edit/delete, validation, and recovery after restart.
3. Build the responsive UI: desktop navigation and tray start/stop/project actions; Android bottom navigation; accessible forms and keyboard shortcuts.
4. Build activity history and reporting: date/project filters, daily/weekly/monthly/project totals, CSV export, and local backup/restore.
5. Build online mode: PHP schema/API, a manually configured personal sync key, authenticated HTTPS requests, UUID records, soft deletes, and last-write-wins conflict handling surfaced to the user.
6. Verify: unit tests for duration, overlap, migrations, and sync merge; integration tests for SQLite/PHP contracts; manual Android and desktop acceptance checks.
7. Package: Windows installer plus portable ZIP; macOS DMG; Linux archive/package; Android APK/AAB. Copy the finished repository to `SHARE/`, initialize its Git history, and create its README and release notes.

## Data model

`projects`: UUID, name, color, archived, timestamps, deleted marker.

`entries`: UUID, project UUID, start/end UTC timestamps, description, timestamps, deleted marker. A running entry has a null end time. The app prevents more than one running entry and rejects invalid or overlapping time ranges.

`settings`: local display and sync configuration only. Credentials are stored using the platform secure store, never in SQLite or exported backups.

## Sync contract

The client uploads changed project/entry records and downloads records newer than a cursor. Every mutable record has a UUID, `updated_at`, and tombstone marker. The server requires a user-created personal sync key sent over HTTPS; it stores only a keyed hash. The initial rule is last-write-wins by server-validated `updated_at`; a conflict is logged locally so it can be inspected. This is deliberately the smallest reliable cross-device sync model.

## Acceptance criteria

- A user can create projects, start/switch/stop a timer, and safely resume after app restart.
- A user can add/edit/delete past entries and get correct filtered totals.
- Local data remains usable with no network.
- A configured second device receives projects and entries without exposing the sync key or accepting unauthenticated writes.
- The Windows release has installer and portable builds; Android has a release build; desktop target builds are documented and reproducible.
