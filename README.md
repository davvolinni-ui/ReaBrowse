# ReaBrowse

ReaBrowse is a fast audio, MIDI, FX, instrument, and action browser for REAPER. It provides native preview playback, tempo and key synchronization, library search, tags, favorites, classification, and drag-and-drop workflows.

This repository is the official ReaPack distribution source for ReaBrowse.

## Requirements

- Windows x64
- REAPER 7.0 or newer
- ReaImGui 0.9 or newer
- SWS Extension
- ReaPack (for repository installation)

MIDI audition requires a selected REAPER track containing an instrument.

The optional js_ReaScriptAPI extension improves native folder selection and
mouse/window detection. ReaBrowse falls back to manual folder entry and other
available APIs when it is not installed.

The SQLite helper, database worker, and ReaBrowse native companion DLL are
included in the package and do not need to be installed separately.

## Install with ReaPack

1. In REAPER, open **Extensions > ReaPack > Import repositories**.
2. Import this URL:

   ```text
   https://raw.githubusercontent.com/davvolinni-ui/ReaBrowse/main/index.xml
   ```

3. Synchronize packages.
4. Find and install **ReaBrowse**.
5. Restart REAPER so the native companion extension is loaded.
6. Open the Action List and run **ReaBrowse**.

ReaPack installs the main script and runtime files under `Scripts/ReaBrowse` and the native companion under `UserPlugins`.

## Release status

The current package is a release candidate. Back up important REAPER settings and project data before testing prerelease software.

## Support

Questions, bug reports, and release discussion:

[Official ReaBrowse support thread](https://forum.cockos.com/showthread.php?p=2958956#post2958956)

## License

ReaBrowse is distributed under its included [EULA](ReaBrowse/EULA.md). Bundled third-party components retain their respective licenses and notices as documented in [THIRD_PARTY_NOTICES.md](ReaBrowse/THIRD_PARTY_NOTICES.md).

This repository does not grant an open-source license to ReaBrowse merely by making its distribution files publicly accessible.
