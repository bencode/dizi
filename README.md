# Dizi

An iPhone app for practicing the dizi (Chinese bamboo flute) along a score: open a score, set the tempo, and play with a metronome while the screen shows, live, whether each note is high or low.

See [the product](docs/product.md).

## Development

Requires Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [SwiftLint](https://github.com/realm/SwiftLint):

```sh
brew install xcodegen swiftlint
```

```sh
cd App
xcodegen generate   # after changing project.yml
open Dizi.xcodeproj
```

`App/project.yml` defines the project; the generated `Dizi.xcodeproj` is committed so it opens without XcodeGen.

Before committing, run every check (format, lint, project sync, build, tests):

```sh
scripts/check.sh
```

See [AGENTS.md](AGENTS.md) for what each check enforces.
