# Contributing to Sendle

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Report a bug or ask for a feature

Open an [issue](https://github.com/quike/sendle/issues). For a bug, include:

- your macOS version, and whether your Mac has Apple silicon or Intel;
- how you send: by email (and with which provider) or over USB (and to which Kindle);
- what you did, what you expected, and what happened instead;
- the lines around the problem from the logs screen (turn on **Settings › General › Show logs**). Passwords never appear there, but check for book titles or addresses you'd rather not share.

## Build and test

Sendle builds with the Command Line Tools alone; Xcode isn't needed. [Development](README.md#development) in the README shows how to build, test and run it, and the environment variables that point it at a fixture library or a mock Kindle.

## Make a change

1. Fork the repository and branch from `main`.
2. Write the test first, then the code that makes it pass.
3. Keep both of these green. CI runs them on every pull request:

   ```bash
   swift test
   swift format lint --strict --recursive Package.swift Sources Tests
   ```

4. If you change what the panel looks like, add before and after screenshots to the pull request. Snapshot mode renders every screen without clicking through them (`SENDLE_SNAPSHOT_DIR`, see the README), and `./scripts/readme-screenshots.sh` updates the README's images.
5. Open a pull request against `main`. Its title follows [Conventional Commits](https://www.conventionalcommits.org), because it becomes the commit on `main`.

## Conventions

- **No third-party dependencies.** Sendle uses what macOS and Swift ship with.
- **One target per layer.** The rules live in `SendleDomain`, which imports only Foundation. Each outside system (Books, EPUB, covers, SMTP, mail, USB, persistence) has an adapter target of its own, `SendleUI` holds the view models and SwiftUI views, and `Sendle` wires them together in `Composition.swift`.
- **It must build with the Command Line Tools.** Keep SwiftUI state in view models: no `@State`, `@Entry` or `#Preview`, which need Xcode's macros.
- **Books' files are read-only.** Sendle never writes to the Books library or to a book's file. Edits apply to the copy it sends.
- **Style** comes from `.editorconfig` and `.swift-format`: 2-space indents and 100 columns. Comments say only what the code can't.
- **Commits** are one Conventional Commits title line, such as `fix(panel): drop the Undo of a delete that an Eject or send made final`, with the details in the pull request. semantic-release reads them to pick the next version and write the release notes.
- **Pull requests** are squash-merged, and their branch is deleted.

## Coding agents

Agents working on Sendle follow [AGENTS.md](AGENTS.md).

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
