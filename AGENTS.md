# Peperete

This is a private, local macOS board with a public-source-ready codebase.

- Keep the product small: boards, columns, cards, notes, due dates, completion, archive.
- Use the same Store implementation for app, widget and CLI. Never write boards.json directly.
- Store mutations must lock, re-read the latest file, validate, back up, and save atomically.
- Real user data belongs outside this repository or in ignored private/. Never commit it.
- Run swift test for storage/CLI changes and make app for SwiftUI or widget changes.
- No cloud account, telemetry, service credentials, or automatic sync.
- Prefer the local peperete command for ticket management after migration, rather than Trello.
- The CLI is at .build/release/peperete after make build; use its absolute path from other folders.
- Begin with doctor, boards and columns. Use card IDs for get/update/move/complete/archive.
- Import adds only missing IDs and does not overwrite existing cards.
- No deletion commands. Archive retains recoverable data.
- Device synchronization and iOS are outside the first version's scope.
