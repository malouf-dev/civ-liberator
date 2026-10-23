# Civ Liberator

Create a separate Mac copy of your installed **Civilization V or VI** that opens without Steam. Your Steam installation stays untouched.

## Get started

Paste this into Terminal:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/malouf-dev/civ-liberator/main/install.sh)"
```

This downloads the current `main` branch into a temporary folder and starts setup. Nothing is pinned to a release or commit. The installer runs without saving a separate script file and cleans up its temporary downloads afterward; your installed game and chosen data folder remain.

Choose your game, choose where to keep it and its saves, then confirm. Press **Return** to accept the choice shown in each prompt. Setup can also copy downloaded mods and hide unavailable online menus.

Open **Sid Meier's Civilization V.app** or **Sid Meier's Civilization VI.app** from the folder you chose.

If you already downloaded the project, open its folder in Terminal and run `bash liberate.sh` instead. The online command requires this repository and its files to be publicly accessible on GitHub.

## What you need

- An installed Mac Steam copy of Civ V or VI, with your expansions already downloaded.
- macOS 11 or later is the build target. Tested on Apple Silicon with macOS 27.0.1; older macOS versions and physical Intel Macs remain untested.
- Civ V needs Rosetta on Apple Silicon. The examined Civ VI build supports Intel and Apple Silicon.
- Enough free space for a separate game copy.

No Python, Homebrew or Xcode is needed. Keep the project's `dependencies` folder beside `liberate.sh`. Run as your normal user, without `sudo`.

## Games, saves and mods

Installed expansions, single-player and hotseat are retained. Compatible downloaded mods can be copied; enable them in **Mods** (Civ V) or **Additional Content** (Civ VI).

Steam online play, achievements, cloud saves and automatic game/mod updates are unavailable. Mod compatibility varies. Existing Steam saves are **not copied automatically**.

By default, the app goes in `/Applications`, or `~/Applications` if that folder is not writable. Saves and mods go here:

| Game | Folder | Mods subfolder |
|---|---|---|
| Civ V | `~/Documents/Games/Civilization V` | `MODS` |
| Civ VI | `~/Documents/Games/Civilization VI` | `Mods` |

Keep the data folder, including its hidden files. If the destination already contains an app or Steam shortcut, setup asks before replacing it and keeps a backup. Declining leaves it untouched. Unattended replacement requires both `--yes` and `--replace`.

## Help

Run `bash liberate.sh --help` for command-line options. For save migration, troubleshooting, compatibility details and rebuilding, see [the advanced guide](docs/advanced.md).

This is an unofficial project. Project code uses LGPL-3.0; dependencies retain their own licenses. See [LICENSE](LICENSE) and the [source and license details](docs/advanced.md#dependencies-source-and-rebuilding). Game purchases are required; no playable games or DLC are supplied.
