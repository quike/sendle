# Recorded replies

The Open Library JSON and HTML files are real replies, recorded on 2026-10-27 with
`curl -sL -A "Sendle/dev (+https://github.com/quike/sendle)"` at the URL the adapter asks for,
then trimmed to the fields the adapter reads. Nothing here comes from anyone's own library.
The Google Books files say below which of them are recordings and which are written by hand.

## openlibrary/

| File | Recorded from | Edits |
|---|---|---|
| `isbn-spanish.json` | `/isbn/9786070714863.json` (it redirects to `/books/OL38570141M.json`): Cien años de soledad, Diana, 2012 | trimmed |
| `isbn-ten-only.json` | `/isbn/9788439711087.json` (`/books/OL48571928M.json`): Cien años de soledad, Mondadori, 1988 | trimmed; `covers` was `[14359127]` and is now `[-1, 14359127]`, because no real edition with only an `isbn_10`, no `authors` and a leading `-1` cover turned up |
| `isbn-two-authors.json` | `/isbn/9780060114183.json` (`/books/OL28176709M.json`): One Hundred Years of Solitude, Harper & Row, 1970 | trimmed |
| `work-OL274505W.json` | `/works/OL274505W.json` | trimmed to `key`, `title`, `authors` |
| `author-OL27363A.json`, `author-OL2631013A.json` | `/authors/OL27363A.json`, `/authors/OL2631013A.json` | trimmed to `key`, `name` |
| `search-cien-anos.json` | `/search.json?title=Cien años de soledad&author=Gabriel García Márquez&limit=5&fields=key,title,author_name&lang=es` | trimmed to `numFound`, `docs` |
| `editions-OL274505W.json`, `editions-OL25917022W.json` | `/works/OL274505W/editions.json?limit=50`, `/works/OL25917022W/editions.json?limit=50` | every entry kept, trimmed to the fields the adapter reads |
| `not-found-404.html` | `/isbn/9788408172277.json`: Open Library has no record of this ISBN (Los ritos del agua, Planeta, 2017) | the page's head and body cut down to a title and a heading |
| `placeholder.gif` | `https://covers.openlibrary.org/b/id/99999999999.jpg`: the one-pixel image sent for a cover that doesn't exist | none |
| `cover.jpg` | made for the tests: an 80 × 120 gradient, over 1,000 bytes like a real cover | not a recording |
| `search-empty.json` | the shape of a search with no results | written by hand |
| `html-200.html` | a captive-portal page, as a hotel network answers any request | written by hand |
| `unavailable-503.html` | a short error page | written by hand |

## google/

There is no API key to record with, so most of these are written by hand from the `volumes`
shape in Google's Books API reference. Their volume IDs are made up, and so are the books' details.

| File | Recorded from | Edits |
|---|---|---|
| `quota-429.json` | `/books/v1/volumes?q=isbn:9788408172277`, with no key: the quota-0 answer every keyless call gets | none |
| `bad-key-400.json` | the same URL with `&key=test-key`, which Google rejects as a key it doesn't know | none |
| `search-isbn.json` | an ISBN search that finds one volume | written by hand |
| `volume-los-ritos-del-agua.json` | `volumes/{id}` for that volume: every `imageLinks` size, a subtitle, both ISBNs, and a date with a day | written by hand |
| `list-cien-anos.json` | a title-and-author search: three volumes, with ISBN-10 listed before ISBN-13, an ISBN-10 only, two authors, and only an `OTHER` identifier | written by hand |
| `search-empty.json` | a search with no results, which has no `items` | written by hand |
| `forbidden-403.json` | a key whose project doesn't have the Books API enabled | written by hand |
| `not-found-404.json` | `volumes/{id}` for an ID Google doesn't know | written by hand |
| `html-200.html` | a captive-portal page, as a hotel network answers any request | written by hand |

The cover images the tests need (the 128 × 170 placeholder, a 300 × 48 banner and a 400 × 600
cover) are drawn with CoreGraphics in `GoogleBooksCatalogueTests.swift`, not stored here.
