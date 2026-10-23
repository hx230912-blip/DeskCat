# DeskCat 🐈

**A tiny pixel cat that gets things done on macOS.**

DeskCat is an experimental native macOS desktop companion with a floating window and a Trash drop target.

## Build a double-clickable DeskCat.app

Requirements: macOS 13+, Swift toolchain / Xcode Command Line Tools.

Download or clone this repository. In Terminal:

```bash
cd /path/to/DeskCat
bash build-app.sh
```

This builds a release executable and creates **`dist/DeskCat.app`**. Finder will reveal it. Double-click to launch. You can optionally drag it into Applications. When you change the code, rerun the script and replace the older app.

This is a **local development build**, not a notarized public release. The build has not yet been tested on your Mac. Quit an older running DeskCat before launching the new version.

## Current features

- Transparent floating AppKit window with programmatically drawn pixel-art cat, desk and bin
- Move the panel by dragging
- Click the cat for quick actions (Calendar, Downloads, current clipboard text)
- Drag Finder test files onto the bin, confirm moving them to macOS Trash
- Basic visual feedback and animation-state scaffold

Meeting notifications, clipboard history, a full task manager, and polished sprite animations are not yet implemented.

## Safety

Use disposable files to test Trash actions. The app does not permanently delete files. There is no automatic update mechanism yet.

## License

MIT for code; future artwork may use a separate license.
