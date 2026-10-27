<p align="center">
  <img src="docs/icon.png" width="128" alt="Sendle's icon: an open book">
</p>

<h1 align="center">Sendle</h1>

<p align="center">Send the books in Apple Books to your Kindle, from the menu bar.</p>

<p align="center">
  <a href="#download"><b>Download</b></a> &nbsp;·&nbsp;
  <a href="#getting-started"><b>Getting started</b></a> &nbsp;·&nbsp;
  <a href="#development"><b>Development</b></a> &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md"><b>Contribute</b></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Built%20with-Swift-F05138?logo=swift&logoColor=white" alt="Built with Swift">
  <img src="https://img.shields.io/badge/macOS%2014%2B-555555?logo=apple&logoColor=white" alt="macOS 14 or later">
  <a href="https://github.com/quike/sendle/releases/latest"><img src="https://img.shields.io/github/v/release/quike/sendle?label=Release&color=2ea44f" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-2ea44f" alt="License: MIT"></a>
  <a href="https://x.com/quike"><img src="https://img.shields.io/badge/Follow-%40quike-000000?logo=x&logoColor=white" alt="Follow @quike on X"></a>
</p>

<p align="center">
  <img src="docs/hero.png" alt="Sendle's panel three times: the library with three books selected to send by email, the queue sending them, and the books on a Kindle plugged in over USB">
</p>

Apple Books has no way to put a book on a Kindle. Sendle reads your Books library, shows it in a small panel under the menu bar, and sends any EPUB or PDF you added yourself to your Kindle: by email through Amazon's Send to Kindle, or straight over the USB cable.

## What it does

- **Shows your Books library** in a dark panel under the menu bar: grid, list or shelf (the newest books stay above the list), sorted by date added, title or author, with an A–Z bar for big libraries, search and filters.
- **Sends by email** through your own Gmail, iCloud, Fastmail or other account, using an app password kept in the Keychain. Before sending, Sendle repacks each EPUB and fixes the problems that make Amazon reject or garble it.
- **Copies over USB** to a Kindle that mounts as a drive. PDFs go as they are; EPUBs are converted to AZW3 with [boko](https://github.com/zacharydenton/boko) first, with a cover thumbnail the Kindle shows.
- **Knows what's on your Kindle.** With the Kindle plugged in, the library marks which books are already on it, an On Kindle view lists everything the Kindle holds, and sending a book that's already there asks whether to skip, keep both or replace it.
- **Lets you fix a book's details** (title, author, year, ISBN, language and cover) for the copies it sends, without ever touching Books' own files.
- **Deletes books from the Kindle,** one at a time, with a few seconds to undo.
- **Hides books you don't want to see** in Sendle, with a few seconds to undo, and a Hidden scope that brings them back. Books' own library stays as it is: **Show in Books** opens a book there, where you can delete it.
- **Explains every problem** with what happened and a button that fixes it, and shows a logs screen when you want to see what's going on underneath.

## Download

Get `Sendle-<version>.dmg` from [Releases](https://github.com/quike/sendle/releases), open it and drag Sendle into Applications. Then open Sendle from Applications and look for the book in the menu bar.

The first time, macOS stops it because it isn't notarized. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to Sendle.

### Check what you downloaded

Every image comes with its SHA-256:

```bash
shasum -a 256 -c Sendle-1.0.0.dmg.sha256
```

Each image also carries a build provenance attestation, which proves GitHub built it from this repository's code:

```bash
gh attestation verify Sendle-1.0.0.dmg --repo quike/sendle
```

### Why the app is not notarized

Notarizing needs a paid Apple Developer ID. Sendle is signed ad hoc instead, so no personal certificate ever leaves a developer's Mac, and the release images are built on GitHub's machines from the tagged code.

### Remove it

1. Quit Sendle from its menu (right-click the book in the menu bar).
2. Delete Sendle from Applications.
3. Delete `~/Library/Application Support/Sendle` and `~/Library/Caches/Sendle`.
4. In Keychain Access, delete the password named `io.github.quike.Sendle.smtp`, and the one named `io.github.quike.Sendle.google-books` if you added a Google Books key.
5. Remove Sendle from **System Settings › Privacy & Security › Full Disk Access**, and from **General › Login Items** if you turned on Launch at login.

## Requirements

- **macOS 14 or later**, on Apple silicon or Intel.
- **Full Disk Access** for Sendle, so it can read the Books library (see below).
- **For email:** your Kindle's Send to Kindle address, and an email account with an app password. The account's address must be on Amazon's approved senders list.
- **For USB:** a Kindle that shows up as a drive when plugged in. EPUBs also need [boko](https://github.com/zacharydenton/boko#install) installed (`cargo install boko`). Without it, PDFs still go over USB and EPUBs go by email.

## Getting started

### Let Sendle see your Books library

macOS keeps the Books library private, and on recent versions it denies access without asking. Sendle only reads the library, never changes it, and nothing leaves your Mac unless you send a book.

1. Open Sendle. The welcome screen asks for access.
2. Click **Open Privacy Settings** and turn on **Sendle** under Full Disk Access. If it isn't listed, click **+** and choose Sendle, or drag it in from Finder.
3. Come back. Sendle checks every few seconds and notices by itself. If it doesn't, quit Sendle from its menu and open it again.

### Set up email

In the panel, click **Set up Kindle email** (or open **Settings › Kindle** and **Settings › Sender**):

<p align="center">
  <img src="docs/settings.png" width="400" alt="Settings › Sender, with iCloud chosen and a sender address filled in">
</p>

| Send with | Server | App password |
|---|---|---|
| Gmail | `smtp.gmail.com`, port 465 | [Create one](https://myaccount.google.com/apppasswords) in your Google account. It needs 2-Step Verification. |
| iCloud | `smtp.mail.me.com`, port 587 | An app-specific password from [account.apple.com](https://account.apple.com). |
| Fastmail | `smtp.fastmail.com`, port 465 | Settings › Privacy & Security in Fastmail. |
| Other | your server, TLS or STARTTLS | |

Then add the sender address to Amazon's approved list: [Amazon › Preferences › Personal Document Settings](https://www.amazon.com/mycd). **Send test** saves the setup and emails your Kindle a short document, so you know it all works.

Outlook.com doesn't work: it only allows sign-in through OAuth, which Sendle doesn't support.

### Set up USB

<p align="center">
  <img src="docs/usb.png" width="820" alt="Three books selected to copy to a Kindle plugged in over USB, and the queue copying them">
</p>

Plug in the Kindle. Its chip appears next to Kindle email in the panel, and books copy to it straight away. For EPUBs, install boko; Sendle looks for it in `~/.cargo/bin`, `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, or wherever you point it under **Settings › USB › Choose…**.

## Using it

Sorted by title or author, the library gets an A–Z bar to jump through it. **Full** shows every letter, all the time. **Compact** shows only the letters that have books, when the pointer is over it. Choose one under **Settings › General**.

<p align="center">
  <img src="docs/az.png" width="820" alt="The A–Z bar beside the panel: Full, at the letter M, and Compact, while dragging to P">
</p>

| Do this | To get this |
|---|---|
| Click the book in the menu bar | Open or close the panel |
| Right-click the book in the menu bar | Settings, Reveal Sendle Data, About and Quit |
| Click a destination chip | Make it where Send and quick-send go: email is blue, USB is green |
| Click a book, ⌘-click, ⇧-click | Select one, add or remove one, select a range |
| Hover a cover and click the paper plane | Quick-send that book to the active destination |
| Hover a book and click the pencil | Edit its details |
| Return | Send the selection |
| Click or drag along the A–Z bar | Jump to a letter (sort by title or author first) |
| Right-click a book › Edit Details…, or ⌘I | Change its title, author, year, ISBN, language or cover |
| 🌐 or ⌘L in a book's details | Look the book up online |
| Right-click a book › Hide from Sendle | Hide it, or the selected books, from Sendle; the Hidden scope lists them, with Show in Sendle |
| Right-click a book › Show in Books | Open it in Books, where you can delete it |
| Library / On Kindle switch | With a Kindle plugged in, see what's on it |
| Click a book on the Kindle | Its details, Edit in Library, or Delete… |
| ⌘Z, or Undo on the toast | Bring back a book you just deleted from the Kindle or hid from Sendle |
| Hover the Kindle chip | Eject it |

| Key | Action |
|---|---|
| ⌘1, ⌘2, ⌘3 | Grid, list, shelf |
| ⌘F | Search |
| ⌘A | Select every book that can be sent |
| Arrow keys | Move the selection |
| ⌘R | Read the Kindle again (On Kindle side) |
| ⌘, | Settings |
| Esc | Close whatever is on top, then clear the selection, then close the panel |

While books are sending, the menu bar shows `↑ 2/3`, and you can close the panel. A red dot means something needs you.

### Settings

- **General:** Launch at login; Controls (the send bar and A–Z bar attached to the panel, or floating beside it); A–Z bar (Full or Compact); Sort authors by (Surname or First name, which also decides how authors are written into the books Sendle sends); Show book format; Show logs.
- **Kindle:** your Kindle email addresses, one of them active.
- **Sender:** the account books are sent from, with Send test.
- **USB:** where boko is.
- **Online lookup:** the catalogues 🌐 asks (Open Library and Apple Books, and Google Books with your own free API key).

### Editing a book's details

<p align="center">
  <img src="docs/edit.png" width="400" alt="The edit sheet for Great Expectations, with a new author name and year, and a box to rename the author's other books too">
</p>

Edits change only the copy Sendle sends; Books' library and files stay untouched. Each field shows what changed and can go back to the original with ↺. Hovering a book also shows a pencil beside the paper plane that opens the sheet. A pencil on the cover marks an edited book: send it again to update your Kindle. Renaming an author can update all their books at once. PDFs take a title and author only, which go into the file name.

Press 🌐 in the sheet, or ⌘L, to look the book up online. Sendle searches by the ISBN in the sheet, or by title and author when there isn't a valid one, and shows each detail that differs in a blue bubble under its field. **Use** fills the field and **Undo** puts back what it held; **Use all** fills every bubble. When the edition has a cover, a row above the title offers it with **Use cover**. The ▾ beside a source's name switches to another source. A book with no ISBN, or one no source knows, gets a list of editions: pick yours, or choose **None of these** or **Skip** to leave the book as it is. Nothing changes until you press **Save**.

## Privacy

Sendle runs on your Mac. It talks to your own email account's server when you send a book by email, and to the lookup sources you have on only when you press 🌐. It reads the Books library and never writes to it. [Privacy](docs/PRIVACY.md) lists everything it keeps and where.

## Limitations

- **Newer Kindles over USB:** the Kindle Scribe and every Kindle from 2024 on don't mount as a drive (they use MTP), so they only work by email. Sendle is tested with a Kindle Paperwhite 11th gen.
- **Books bought in Apple Books** are protected by Apple's DRM and can't be sent. Sendle shows them, but never removes DRM.
- **One book per email,** and emails are limited to Amazon's 50 MB.
- **Amazon reports email problems by email.** Sendle can say a book reached Amazon, not that it reached the Kindle.
- **Kindle collections** and editing books on the Kindle itself aren't supported.
- **Deleting a book from your library** happens in Books. Sendle never writes Books' library, so it hides books instead and opens Books to delete them.

Planned and proposed features are in [Issues](https://github.com/quike/sendle/issues).

## Development

Want to help? Start with [CONTRIBUTING.md](CONTRIBUTING.md).

Sendle is a Swift 6 package with no third-party dependencies, split into one target per layer: the domain (`SendleDomain`), one adapter per outside system (Books, EPUB, covers, SMTP, mail, USB, persistence), the SwiftUI views (`SendleUI`) and the AppKit shell (`Sendle`). It builds with the Command Line Tools alone; Xcode isn't needed.

```bash
swift build
swift test
swift format lint --strict --recursive Package.swift Sources Tests
```

To run the real app, build it into `build/Sendle.app`:

```bash
./scripts/make-signing-identity.sh
./scripts/build-app.sh
open build/Sendle.app
```

`make-signing-identity.sh` creates a local "Sendle Local Signing" certificate, once. Without it the app is signed ad hoc, and macOS forgets its Full Disk Access and Keychain approval on every rebuild.

### Screenshots

The screenshots here never show a real library. `scripts/make-fixture-library.swift` writes a Books-style library of public-domain books with drawn covers, by default to `build/fixture-library`, for `SENDLE_LIBRARY_DB` to read. To render the panel with it and write the images in `docs/`, run (it needs ImageMagick, `brew install imagemagick`):

```bash
./scripts/readme-screenshots.sh
```

| Variable | What it does |
|---|---|
| `SENDLE_DATA_DIR` | Use another data folder instead of `~/Library/Application Support/Sendle`. |
| `SENDLE_LIBRARY_DB` | Read this Books-style `.sqlite` file instead of the real Books library. |
| `SENDLE_SNAPSHOT_DIR` | Render the panel's screens to PNG files in this folder and quit. Needs `SENDLE_DATA_DIR`. |
| `SENDLE_VERSION` | The version `build-app.sh` stamps into the app (default: the latest `v*` tag). |
| `APP_PATH`, `CODESIGN_IDENTITY`, `UNSIGNED` | Where `build-app.sh` puts the app, and how it signs it. |
| `SENDLE_SKIP_KEYCHAIN_TESTS` | Skip the tests that use the real Keychain (CI sets it). |
| `SENDLE_TEST_SMTP_HOST`, `_PORT`, `_USER`, `_PASS`, `_TO` | Run the live SMTP test against a real server. |
| `SENDLE_REAL_LIBRARY_CHECK=1` | Run the test that reads your real Books library (the terminal needs Full Disk Access). |
| `SENDLE_DISK_IMAGE_CHECK=1` | Run the USB tests against a disk image laid out like a Kindle. |

### Releasing

Releases come from [semantic-release](https://semantic-release.gitbook.io) through the shared [workflow-github](https://github.com/quike/workflow-github) release workflow. Every commit follows [Conventional Commits](https://www.conventionalcommits.org), and that decides the next version.

On every push to `main`, CI lints and tests. If the commits since the last release call for one, semantic-release tags it and publishes a GitHub release with notes from the commits. A macOS job then builds the disk image with that version and attaches it and its SHA-256 to the release. The releases are the changelog.

To build the same image locally:

```bash
brew install uv
SENDLE_VERSION=1.0.0 UNSIGNED=1 ./scripts/release-mac.sh
```

It writes `build/Sendle-1.0.0.dmg` and `build/Sendle-1.0.0.dmg.sha256`.

## License

[MIT](LICENSE). boko is a separate program under the GPL-3.0; Sendle runs your installed copy and doesn't include it.
