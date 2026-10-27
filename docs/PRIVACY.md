# Privacy

Sendle runs on your Mac. It talks to your own email account's server when you send a book by email, and to the lookup sources you have on only when you press 🌐.

## What it keeps, and where

| Where | What |
|---|---|
| `~/Library/Application Support/Sendle/` | `settings.json` (your choices, Kindle addresses, sender address and server, but no password), `history.json` (the last 1,000 sends), `edits.json` and `edit-covers/` (your book edits), `editions.json` and `kindles/` (caches). A file Sendle can't read is moved aside as `<name>.corrupt-<time>.json`, never overwritten. |
| `~/Library/Caches/Sendle/covers/` | Cover thumbnails |
| Your login Keychain | The app password, under `io.github.quike.Sendle.smtp`, and your Google Books API key, under `io.github.quike.Sendle.google-books` |
| `$TMPDIR/Sendle-staging/` | The copy of each book being prepared, deleted after every send and at launch |
| Your Kindle | The books you send to `documents/`, their cover thumbnails in `system/thumbnails/`, and books you delete, held in `.sendle-held/` until the Undo time is over |

## What it reads, logs and sends

- Sendle reads the Books library and book files, and never writes to them. Books that are only in iCloud are never opened, so nothing downloads.
- Logs live in memory until Sendle quits. They also go to the macOS log under `io.github.quike.Sendle`, marked private. Passwords and your Google Books API key never appear in either.
- When you press 🌐 in a book's details, Sendle sends the book's ISBN, or its title and author, to the lookup sources you have on (Open Library, Apple Books, Google Books), then fetches the covers they point to. A search by title and author also sends the book's language to Open Library and Google Books. Each request carries Sendle's name and version; Apple Books also gets your Mac's region, and Google Books your API key.
- An email carries the book, its title as the subject, your sender address and "Sent by Sendle."

To remove everything Sendle keeps, see [Remove it](../README.md#remove-it).
