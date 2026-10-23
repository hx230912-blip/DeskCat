# DeskCat 🐈 — v0.4 developer preview

A native macOS floating desk companion. Written in Swift, AppKit, EventKit and UserNotifications.

## Features
- Movable 256×176 workstation; click without moving to interact, drag more than 4 points to reposition. Position persists.
- Different actions for the cat, monitor, paper stack, desk and Trash.
- Lightweight grooming, sleep, walk, celebration and paper-throw *overlay effects*. These are not yet frame-by-frame cat character sprites.
- Local task list, with optional notifications after N minutes. Task completion triggers a celebration.
- Upcoming 48-hour calendar events, with optional local reminders five minutes before future events when you open the meeting view and grant permission.
- Confirmed file moves to macOS Trash; a paper animation plays first. This is not permanent deletion.

## Build a macOS .app

Requires macOS 13+ and Xcode Command Line Tools.

The approved image `DeskCatScene.png` is not stored in GitHub yet. Copy your previously approved image to:

`Sources/DeskCat/Resources/DeskCatScene.png`

Then run:

```bash
bash build-app.sh
```

The app is generated at `dist/DeskCat.app`. Quit older instances before launching the new build.

**Important:** This is an untested developer preview. Please use disposable files to test Trash. The image resource must be packaged inside `DeskCat_DeskCat.bundle`, which `build-app.sh` handles.

## Next milestones
- True multi-frame sprites for licking, sleeping, walking, carrying and throwing
- Non-modal task management window with task editing and removal
- Background calendar refresh and reminders independent of opening the meeting list
- Hit testing based on alpha and accessibility improvements
- Code signing, notarization and release packaging

## License
MIT for code. Artwork licensing is separate.
