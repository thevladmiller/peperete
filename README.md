# Peperete

A small, private board for your Mac. Boards → columns → cards. Nothing to sign into.

Drag cards between columns, write notes, set an optional due date, mark work complete,
and archive cards when you want them out of the way. Search covers card titles and notes.
New boards begin with **To do / Doing / Done**; imported boards retain their existing columns.
Completion and column placement are separate: moving to Done does not automatically tick completion.

## Build and run

Requires macOS 14 or newer, Xcode with a Swift 6 compiler, and Python 3 to regenerate
the Xcode project. There are no third-party packages or services.

```sh
make test
make app
open build/Build/Products/Release/Peperete.app
```

Or open `Peperete.xcodeproj` in Xcode, choose the Peperete scheme, and Run.
The app and bundled widget use local ad-hoc signing. This is a development build,
not an App Store or notarized release. No Developer account is configured in the repository.

## Desktop widget

Launch the app once, then right-click your desktop → Edit Widgets → Peperete.
Choose a small, medium or large widget. It shows incomplete cards, earliest due dates
first. Click the circle to complete a card or the title to open it in the app.
macOS controls background refresh timing; opening or changing a card in Peperete
requests an immediate timeline refresh. Command-line changes become visible on the
next system refresh or when the open app polls the data file (every three seconds).

The app and local command use ordinary local storage. The widget is sandboxed and
has a narrow file-access entitlement for only the Peperete Application Support folder,
including the lock and backups needed for completing a card. This supports local ad-hoc
development without an Apple Developer account. App Store distribution would need a
signed App Group and a storage migration rather than this temporary-exception entitlement.

## Your data and devices

Data lives in `~/Library/Application Support/Peperete/boards.json`. Each mutation
locks the file, reads the current version, validates changes, creates a backup of
the previous version, and saves atomically. Backups are retained in `Backups/`;
they are not automatically pruned. This is ordinary local storage, protected by
your macOS account and disk security, not application-level encryption.

Use the sidebar's `…` menu → Export boards to produce a portable JSON file. Import
on another Mac to add missing boards/cards. Existing IDs are never overwritten, so
re-importing a Trello migration cannot undo local edits. This is a one-time transfer
and backup mechanism, **not two-way synchronization**. For a full move to another Mac,
use a fresh Peperete data folder and import your latest export. Do not share one live
database through Dropbox or iCloud Drive: this version does not resolve sync conflicts.

This first version is macOS-only. An iPhone or iPad app and device synchronization
are not included.

## Trello migration

The app imports Peperete-format JSON, not arbitrary Trello JSON. For a new migration,
run `python3 scripts/import-trello.py INPUT.json OUTPUT.json` on a standard Trello board
export, then import OUTPUT.json. Repeat per board. Core fields are mapped to Peperete;
checklists, labels and comments from the export are appended to notes. Attachment
links are preserved in notes; uploaded file contents are not downloaded automatically.
Original Trello IDs and card links are retained. Original exports should be kept privately.
Historical actions, automations and Power-Ups are not reproduced as app features.

Never put real boards, migration files, screenshots of private cards or credentials
in the public repository. `private/`, app databases, exports with a `.peperete` extension,
and build output are ignored. Arbitrary `.json` exports outside `private/` are not ignored;
store private exports in `private/` or outside the repository.

## Gemini Notebook documentation

Each board can publish one live Markdown source into a folder synchronized by
Google Drive. Open the book button beside the board title, choose the Drive
folder and enter the destination notebook name. Peperete rewrites the same file
after every change and records an append-only activity history, so the notebook
stays useful without creating one source per card.

Use **Prepare link in Gemini** once. It opens Gemini and copies an instruction
for the official Gemini Notebook connected app to attach the Drive file to the
specified personal notebook. In the EEA, connect Gemini Notebook manually in
Gemini's Connected Apps settings first. Peperete never stores a Google password
or OAuth token. After the source is attached, Drive/Notebook handles subsequent
refreshes; Peperete remains the authoritative copy.

The same configuration is available to local automation:

```sh
.build/release/peperete documentation BOARD_ID "/path/in/Google Drive" "Notebook name" "https://notebook.google.com/..."
.build/release/peperete publish
```

## Local assistant interface

```sh
make build
.build/release/peperete doctor
.build/release/peperete boards
.build/release/peperete columns BOARD_ID
.build/release/peperete cards BOARD_ID
.build/release/peperete search "invoice"
.build/release/peperete get CARD_ID
.build/release/peperete create COLUMN_ID "Send proposal"
.build/release/peperete move CARD_ID COLUMN_ID
.build/release/peperete complete CARD_ID true
.build/release/peperete export /path/to/private-backup.json
```

Run `peperete --help` for the complete command list. Commands emit JSON values directly;
errors emit `{"error":"..."}` to stderr and exit nonzero. `dump` is the read-only full
database escape hatch. Use `PEPERETE_DATA_DIR=/absolute/test/folder` to work with a separate
database. No network, tokens, account or listening server is involved.

## Development

`Sources/PepereteCore` is the shared data model and store. `PepereteApp` is the SwiftUI
app, `PepereteWidget` the WidgetKit extension, and `PepereteCLI` the local assistant tool.
The Swift package builds the CLI and tests; Xcode builds the app and widget. Regenerate
the Xcode project after adding or removing Swift files with `make project`.

MIT licensed. Designed for one person using local devices.

An optional GitHub Actions configuration is in `ci/github-actions.yml`. To enable
it, add it to `.github/workflows/build.yml` through an account or token permitted
to manage workflows. The initial repository publishes the template only; automated
GitHub runs are not enabled.
