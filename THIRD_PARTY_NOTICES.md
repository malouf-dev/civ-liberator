# Source and notices

Civ Liberator's shell scripts and Swift helper use LGPL-3.0. See LICENSE and dependencies/GPL-3.0.txt for the incorporated GPL terms.

The bundled `libsteam_api.dylib` is built from inflation/goldberg_emulator, commit `2ad4a39be742baee2037ed40132c2deb4de2301e`. Its license is included at `dependencies/Goldberg-LICENSE.txt`. The corresponding source and the applied build patch are included under `dependencies/source/` and `dependencies/goldberg-build.patch`.

The library also incorporates Protobuf 23.1 (commit `2dca62f7296e5b49d729f7384f975cecb38382a0`) and Abseil (commit `c2435f8342c2d0ed8101cb43adfd605fdc52dca2`). Their source, licenses and notices are retained in `protobuf-23.1-with-abseil.tar.gz`, including the Abseil submodule. Rebuild instructions are in `docs/advanced.md`; the Swift helper source is in `src/`.

The menu rules describe byte offsets, input/output hashes and inserted edits. They require the user's installed game files; they do not bundle original game functions, full UI files, game executables, DLC, mods or saves. Game names and referenced API identifiers belong to their respective owners. This project is unofficial and is not endorsed by Aspyr, Firaxis, 2K or Valve.

Removing copied source excerpts is a technical distribution cleanup, not a determination of rights to distribute circumvention functionality in every jurisdiction. Upstream licenses do not grant rights to the games.
