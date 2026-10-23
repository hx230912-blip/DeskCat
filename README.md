# DeskCat 🐈

**A tiny pixel cat that gets things done on macOS.**

DeskCat is an experimental, native macOS desktop helper. It stays in the corner while you work and will eventually animate file handling, reminders, and task completion.

## Current status: v0.1 scaffold (unverified)

This first commit is a **prototype**, not a finished pixel-art app. It uses emoji placeholders, a transparent floating panel, a menu bar item, and a Trash drop target with confirmation. No animation, task list, or meeting integration has been implemented yet.

## Build on a Mac

1. Install Xcode 15 or newer and its command-line tools.
2. Clone this repository and run `swift run` from the project root, or open `Package.swift` in Xcode and run the `DeskCat` executable scheme.
3. Look for the cat near the lower-right corner and the cat icon in the menu bar.
4. **Test only with disposable files.** Drag a test file from Finder onto the trash-bin icon, then confirm the macOS Trash action.

The app has not yet been compiled or tested on macOS in this environment. File access may be affected by macOS permissions.

## Design principles

- Native SwiftUI + AppKit; SpriteKit animation planned.
- Local-first, minimal permissions, no telemetry.
- No permanent deletion: files go to macOS Trash.
- Never delay actual file operations for cosmetic animations.
- Calm by default, animated only on useful interactions.

## Roadmap

- [x] Repository and prototype source structure
- [ ] Verify build and drag/drop on macOS
- [ ] Original pixel cat sprite sheets and animation state machine
- [ ] Non-blocking Trash operation and accessible drop feedback
- [ ] Local quick tasks and break reminders
- [ ] Calendar reminders (opt-in)

## License

MIT for code. Future original artwork may carry a separate license.
