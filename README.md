# Dizi

An iPhone app for practicing the dizi (Chinese bamboo flute) along a score: open a score, set the tempo, and play with a metronome while the screen shows, live, whether each note is high or low.

See [the product](docs/product.md).

## Development

Requires Node 24 (`npm install` at the root), Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [SwiftLint](https://github.com/realm/SwiftLint):

```sh
brew install xcodegen swiftlint
```

```sh
cd apps/ios
xcodegen generate   # after changing project.yml
open Dizi.xcodeproj
```

`apps/ios/project.yml` defines the project; the generated `Dizi.xcodeproj` is committed so it opens without XcodeGen.

Before committing, run every check (format, lint, project sync, build, tests):

```sh
scripts/check.sh
```

See [AGENTS.md](AGENTS.md) for what each check enforces.

## Credits

The demo melody uses dizi recordings by [Hypnotriod](https://freesound.org/people/Hypnotriod/packs/21613/) (CC0), with thanks.
