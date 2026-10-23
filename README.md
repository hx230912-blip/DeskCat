# DeskCat 🐈

**A tiny pixel cat that gets things done on macOS.**

An experimental native macOS helper: a calm cat in your screen corner that reacts to file operations.

## Current status — early prototype, not yet verified on macOS

- Transparent floating AppKit panel and menu bar entry
- Finder file URL drag target on the trash icon
- Explicit confirmation before moving items to the **system Trash**
- File work dispatched off the UI thread, with success/error feedback
- Basic animation state machine using emoji placeholders (not pixel sprites yet)

**No actual pixel-art animation, meeting reminders, task list, or local Mac build verification yet.**

## Run locally

1. Install Xcode 15+ on macOS 13+.
2. Clone the repository.
3. Open `Package.swift` in Xcode and run the `DeskCat` scheme, or try `swift run` in Terminal.
4. Drag only **disposable test files** from Finder onto the bin icon, then confirm.

Note: Finder drag/drop, window placement, and file permissions require testing on a real Mac. The app is not signed or notarized. If you see a compile error, capture the full Xcode diagnostic for the next iteration.

## Roadmap

- [x] Initial Swift package and macOS app entry point
- [x] File drop + confirmation + system Trash service
- [x] Basic visual state coordinator
- [ ] Validate compilation and drag/drop on macOS
- [ ] Original orange-and-white pixel cat sprite sheets and SpriteKit animation
- [ ] Non-blocking confirmation UI and detailed partial-failure feedback
- [ ] Task checklist and break reminders
- [ ] Optional calendar support

## Principles

Calm by default. Animate only when useful. Never permanently delete. Keep files local.

## License

MIT applies to code. Future artwork may be separately licensed.
