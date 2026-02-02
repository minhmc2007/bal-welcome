
# BAL Welcome

**BAL Welcome** is a fullscreen animated welcome and initialization interface for **Blue Archive Linux (Arch-based)**, built with **Flutter Desktop**.
It is designed to run during first boot or session startup, providing a polished transition into the KDE Plasma desktop.

---

## Overview

BAL Welcome delivers a cinematic startup experience inspired by *Blue Archive*, combining video backgrounds, smooth UI transitions, and system integration specific to Arch-based Blue Archive Linux.

This application replaces traditional static greeters with a modern, animated interface while remaining lightweight and purpose-focused.

> **Note**
> Debian-based Blue Archive Linux is **end-of-life (EOL)**.
> Ongoing support targets **Arch-based architecture only**.

---

## Features

* Fullscreen, borderless window
* Looping background video playback
* Smooth animated transitions and UI effects
* Multilingual greeting rotation
* Custom interactive buttons with hover and press feedback
* KDE Plasma integration:

  * Applies a random wallpaper from `/usr/share/backgrounds`
  * Launches Plasma session after completion
* Linux-specific locale initialization using `libc`
* Optimized for Arch-based systems

---

## Technology Stack

* **Flutter (Linux Desktop)**
* **Dart**
* `media_kit` / `media_kit_video` — video playback
* `window_manager` — window control
* `google_fonts` — typography
* `animate_do` — UI animations
* `dart:ffi` — Linux locale handling

---

## System Requirements

* Arch Linux or Arch-based distribution
* KDE Plasma desktop environment
* Flutter with Linux desktop enabled
* Required system components:

  * `glibc`
  * `ffmpeg`
* Plasma utility available in `$PATH`:

  ```bash
  plasma-apply-wallpaperimage
  ```

---

## Build Instructions

BAL Welcome is built as a native Linux binary using the provided build script.

```bash
bash dist/binary_build.sh
```

The script will:

* Compile the Flutter Linux desktop application
* Produce a runnable binary suitable for Blue Archive Linux

---

## Assets

The following asset is required at runtime:

```
assets/video/bg_loop.mp4
```

Ensure the asset path is correctly declared in `pubspec.yaml`.

---

## Behavior Summary

1. Application launches in fullscreen mode
2. Background video begins looping silently
3. Welcome screen is displayed with animated greetings
4. On user interaction:

   * A random KDE wallpaper is applied
   * System initialization screen is shown
5. Plasma session is launched and the app exits

---

## Author

**Architect:** `minhmc2007`

---

## License

GPL3

---
