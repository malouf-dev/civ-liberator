# Civ Liberator

Create a separate Mac copy of your installed **Civilization V or VI** that opens without Steam. Your Steam installation stays untouched.

## Get started

Paste this into Terminal:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/malouf-dev/civ-liberator/main/install.sh)"
```

This downloads the current `main` branch into a temporary folder and starts setup. Nothing is pinned to a release or commit. The installer runs without saving a separate script file and cleans up its temporary downloads afterward; your installed game and chosen data folder remain.

Setup takes you through four steps:

1. Choose your game. The list shows which games Steam has installed.
2. Choose where to install the game, and where to keep its saves and mods.
3. Choose whether to hide unavailable online menus, copy your downloaded mods and enable each installed expansion.
4. Check your choices, then install.

Press **Return** to accept the answer shown in [brackets]. To use a different folder, type its path or drag the folder from Finder into the Terminal window. Setup checks each answer straight away and asks again if a folder can't be used. Press **Ctrl-C** to cancel before the install starts.

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

You can turn off an expansion you don't want to play with: Gods & Kings or Brave New World in Civ V, and Rise and Fall or Gathering Storm in Civ VI. The game then treats it as not owned. Smaller DLC packs stay on. Saves made with an expansion may not load while it is off.

### Change expansions later

Run setup with `--manage`. It finds your copy in `/Applications` or `~/Applications` and asks only about expansions. Then it changes the expansion list inside the app and signs the app again. Nothing is copied and no backup is made. Your other choices, saves and mods stay as they were. It took about a second for Civ V and 12 seconds for Civ VI. Quit the game first. If the signing step is interrupted, run `--manage` again.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/malouf-dev/civ-liberator/main/install.sh)" setup --manage
```

From the project folder, run `bash liberate.sh --manage` instead. `--manage` works on copies made by this version of setup or later. A copy made earlier doesn't record its choices, so run setup once without `--manage` to rebuild it.

Steam online play, achievements, cloud saves and automatic game/mod updates are unavailable. Mod compatibility varies. Existing Steam saves are **not copied automatically**.

By default, the app goes in `/Applications`, or `~/Applications` if that folder is not writable. Saves and mods go here:

| Game | Folder | Mods subfolder |
|---|---|---|
| Civ V | `~/Documents/Games/Civilization V` | `MODS` |
| Civ VI | `~/Documents/Games/Civilization VI` | `Mods` |

Keep the data folder, including its hidden files. If the destination already contains an app or shortcut with the same name, setup says whether it is a full app, an earlier Civ Liberator copy, a shortcut or a Finder alias. It asks before replacing it and keeps a backup. Declining leaves it untouched. Unattended replacement requires both `--yes` and `--replace`.

## Help

Run `bash liberate.sh --help` for command-line options. For save migration, troubleshooting, compatibility details and rebuilding, see [the advanced guide](docs/advanced.md).

This is an unofficial project. Project code uses LGPL-3.0; dependencies retain their own licenses. See [LICENSE](LICENSE) and the [source and license details](docs/advanced.md#dependencies-source-and-rebuilding). Game purchases are required; no playable games or DLC are supplied.
