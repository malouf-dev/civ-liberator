# Advanced guide

[Back to getting started](../README.md)

Run the commands below from the project folder.

## Command-line use

```sh
# Read-only discovery
bash liberate.sh --game 6 --inspect

# Explicit unattended setup
bash liberate.sh --game 6 --yes \
  --destination "$HOME/Applications" \
  --data "$HOME/Documents/Games/Civilization VI"

# Use an explicitly selected Steam copy
bash liberate.sh --game 5 \
  --source "$HOME/Library/Application Support/Steam/steamapps/common/Sid Meier's Civilization V/Civilization V.app"
```

`--no-menus` keeps the original menus. Use it if a game update does not match the bundled, checksum-verified menu patches. `--no-mods` skips mod import. `--yes` accepts the supplied/default choices; it does not permit overwriting unrelated applications.

## macOS and processor support

| Component | Architecture | Compatibility target |
|---|---|---|
| Installer | Bash + bundled universal native helper | macOS 11 Big Sur or later |
| Bundled compatibility library | Universal `x86_64` + `arm64` | Both slices built with macOS 11.0 deployment target |
| Current Steam Civ V executable examined | `x86_64` | Intel natively; Apple Silicon requires Rosetta 2 |
| Current Steam Civ VI executable examined | Universal `x86_64` + `arm64` | Intel or native Apple Silicon |

**macOS 11 is the project's build target, not a promise that every OS/game/hardware combination has been tested.** Both games were packaged and signature-verified on an Apple Silicon Mac running macOS 27.0.1. Physical Intel Macs and macOS 11–26 are untested. A game's own requirements, graphics driver support, or a later Steam game update can impose a higher minimum. Older 32-bit Mac builds, Windows/Linux builds, and Mac App Store editions are not supported. The script does not turn Civ V into an ARM-native game.


Aspyr confirms [64-bit Civ V Mac builds](https://support.aspyr.com/hc/en-us/articles/360020548611-Civilization-V-Mac-FAQ) and [Apple Silicon optimization for Civ VI](https://support.aspyr.com/hc/en-us/articles/29100667201677-New-Monthly-Challenges-to-the-Mac-Version-of-Civilization-VI). See the [Civ VI Mac FAQ](https://support.aspyr.com/hc/en-us/articles/213487546-Civilization-VI-Mac-FAQ) for game-specific requirements. This tool does not improve GPU performance or make unsupported hardware compatible.

## Saves and mods

Defaults:

| Game | Data root | Saves | Mods |
|---|---|---|---|
| Civ V | `~/Documents/Games/Civilization V` | `Saves`, `ModdedSaves` | `MODS` |
| Civ VI | `~/Documents/Games/Civilization VI` | `Saves` | `Mods` |

Each data root also contains `Launcher.log` and a hidden `.runtime-home` for isolated preferences/cache. Keep this directory when moving or deleting the app. The launcher changes environment variables only for the game; it does not redirect your real Library folder. Existing Steam saves are not migrated automatically. Copy save files manually into the corresponding Single/Hotseat/ModdedSaves subfolder as appropriate.

Original Steam data is normally in:

- Civ V: `~/Library/Application Support/Sid Meier's Civilization 5/`
- Civ VI: `~/Library/Application Support/Sid Meier's Civilization VI/Sid Meier's Civilization VI/`

Mod import reads unpacked local mods first, then the selected library's `steamapps/workshop/content/8930` or `289070`. It deduplicates by mod ID and preserves destination mods. Civ VI's Quick Deals, R.E.D. Modpack and Yet (not) Another Maps Pack were imported successfully in integration testing. Packed `.civ5mod` archives and mods lacking a `.modinfo` manifest are skipped; unpack/install those through the game's normal mod flow first. Mods with symlinks are rejected. Mod compatibility with expansions, game versions, macOS and hotseat remains the mod author's responsibility.

## What works and what is unavailable

The script retains installed expansions/DLC and local single-player/hotseat entry points. It derives the DLC list from the local Steam manifest and corresponding Aspyr metadata; it does not download or grant missing content.

Unavailable in the independent copy:

- Steam Cloud and Steam achievements;
- Steam multiplayer, matchmaking and account services;
- automatic Workshop downloads/subscriptions/updates;
- Steam game updates and online account/promotional features hidden by the optional menu cleanup.

The compatibility library's networking is disabled. Menu cleanup is not a system firewall. The local profile currently defaults to `Local Player` and English. Offline menu edits require exact known source hashes and fail safely on version changes. Keeping original menus does not restore online services. Mods and expansions can have their own requirements; this is not a guarantee of every mod or multiplayer mode.

## Recovery and troubleshooting

If menu cleanup reports an unsupported game version, retry with `--no-menus`. This keeps the original menus; it does not restore Steam services. A missing Rosetta error on Apple Silicon means the selected game is Intel-only. Install Rosetta before retrying.

Use `NO_COLOR=1 bash liberate.sh` for plain output. For read-only game discovery, use `bash liberate.sh --game 6 --inspect` (or `--game 5`).

The game is built in a temporary sibling directory and published only after signing and verification. Steam inputs are never modified. Failed builds remove their temporary app; already imported mods/data may remain and are preserved on retry. Interrupted processes or power loss can leave `.civ-liberator-*` folders; inspect them before removing them. The final rename refuses to replace a destination that appeared unexpectedly.

The output is ad-hoc signed, not Developer ID signed or notarized. This project does not disable Gatekeeper, SIP or system protections. Use `Launcher.log` for startup diagnostics. Available disk space must cover the game and any retained backup; APFS sharing is an optimization, not a space guarantee.

## Dependencies, source and rebuilding

`dependencies/libsteam_api.dylib` is built from [inflation/goldberg_emulator](https://github.com/inflation/goldberg_emulator) at `2ad4a39be742baee2037ed40132c2deb4de2301e` with the included CMake patch. Corresponding source archives are included for Goldberg, Protobuf 23.1 (`2dca62f7296e5b49d729f7384f975cecb38382a0`) and Abseil (`c2435f8342c2d0ed8101cb43adfd605fdc52dca2`). The Protobuf archive includes its Abseil submodule. All upstream license/notice files remain in the archives.

To rebuild the native helper using Xcode command-line tools:

```sh
bash tools/build-native.sh
```

This builds both architecture slices with a macOS 11 deployment target, ad-hoc signs the helper and updates `dependencies/native.sha256`. The entry script checks this hash before executing the helper.

To rebuild the library, install Xcode command-line tools, CMake >=3.24, Ninja and Git, then run:

```sh
bash tools/build-dependencies.sh
dependencies/civ-liberator verify 6 "$PWD"
bash tests/smoke.sh
```

Rebuilding updates dependency checksums; review the changes before committing. The normal installer verifies those checksums before modifying its new copy. Checksums detect accidental changes; trust comes from obtaining this repository from a source you trust.

The project's scripts use LGPL-3.0; Goldberg uses its included LGPL-3.0 license and bundled third-party sources retain their own licenses. Game assets remain the property of their respective owners. Menu patches contain byte offsets, inserted fragments and exact input/output hashes. The installer reads original source only from the user’s game and refuses mismatched versions. See [source notices](../THIRD_PARTY_NOTICES.md). This is an unofficial local-copy tool, not an Aspyr, Firaxis, 2K or Valve release.


## Updating main

The online installer fetches `main` directly, with no release, tag or commit pin. Each push becomes what new users download. Keep the scripts, bundled binaries and checksum files consistent in the same push.

Before pushing, run:

```sh
bash tests/smoke.sh
bash tests/menus.sh
bash tests/installer.sh
```

Rebuild changed native code with `bash tools/build-native.sh`. After changing menu rules or library dependencies, run `dependencies/civ-liberator manifest 6 "$PWD"` to refresh their checksums. Menu tests require both supported Steam installations locally.

Downloads use HTTPS. Setup verifies the bundled helper and dependency checksums; these detect mismatched files, not an independently authenticated release. Trust comes from the repository you download. Normal completion, failure and cancellation remove temporary downloads. Force-killing the process or power loss may leave a temporary folder. Installed apps and their data are retained.
