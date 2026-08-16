<img src="icon/icon_round.png" width="76"/>

# gopassforios

An iOS password-store client aimed at [gopass](https://www.gopass.pw/) setups.

This is a fork of [Pass for iOS](https://github.com/mssun/passforios) by
Mingshen Sun — an excellent client, and all of the hard work here is his and
his contributors'. Upstream targets a single [`pass`](https://www.passwordstore.org/)
store, which is the one thing a gopass user tends not to have.

**Not affiliated with the gopass project.**

## Why this fork

gopass stores are ordinary `pass` stores on disk — GPG-encrypted files in a git
repository — so nothing about the format needs porting. Two things differ:

- **Multiple stores.** gopass mounts several repositories at once, each with its
  own git remote and its own recipients. Upstream models exactly one.
- **age encryption.** gopass can use age instead of GPG, including SSH keys as
  recipients. Upstream is GPG-only.

## Status

Early. Today this is upstream Pass for iOS, rebranded so it can be installed
alongside the App Store release — it clones one store and decrypts it, exactly
as upstream does.

| | |
|---|---|
| multiple stores | in progress |
| age backend | planned |

Neither is implemented yet. If you need a working single-store client today,
use [upstream](https://github.com/mssun/passforios) — it's on the App Store and
it's maintained.

## Features

Inherited from upstream:

- Compatible with the Password Store command line tool.
- View, copy, add, and edit password entries.
- Encrypt and decrypt password entries by PGP keys.
- Synchronize with your password Git repository.
- User-friendly interface: search, long press to copy, copy and open link, etc.
- Support one-time password tokens (two-factor authentication codes).
- AutoFill in Safari/Chrome and supported apps.
- Support YubiKey.

## Building

1. Install Go: `brew install go`.
1. Run `./scripts/gopenpgp_build.sh` to build GopenPGP.
1. Open the `pass.xcodeproj` file in Xcode.
1. Set `DEVELOPMENT_TEAM` to your own Apple team, and change the bundle
   identifiers from `com.techneosis.gopassforios` to something you own.
1. Build & Run.

Upstream's [wiki](https://github.com/mssun/passforios/wiki) remains the best
reference for setting up keys and a git remote; the app's configuration is
unchanged from theirs.

## License

MIT — see [LICENSE](LICENSE). Copyright for the original work remains with
Bob Sun and the Pass for iOS contributors.
