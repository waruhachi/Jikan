<h1 align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS-111111?style=for-the-badge" />
  <img alt="Language" src="https://img.shields.io/badge/language-Objective--C%20%26%20Logos-2b2b2b?style=for-the-badge" />
  <img alt="Theos" src="https://img.shields.io/badge/build-Theos-2b2b2b?style=for-the-badge" />
  <img alt="License" src="https://img.shields.io/badge/license-GPLv3-blue?style=for-the-badge" />
  <img alt="Package" src="https://img.shields.io/badge/package-.deb-0a84ff?style=for-the-badge" />
</h1>

<br />
<div align="center">
  <h3 align="center">Jikan</h3>

  <p align="center">
    A lock screen tweak that shows an estimated time until fully charged in a charging platter UI.
  </p>
</div>

## About The Project

Jikan is an iOS jailbreak tweak built with Theos that adds a charging pill/platter to the lock screen.

When charging is detected, it shows estimated time to full charge and applies Quick Action-adjacent material styling so the component blends into SpringBoard's lock screen UI.

## Getting Started

### Prerequisites

- macOS with Xcode command line tools
- [Theos](https://theos.dev) configured
- A jailbroken iOS device/environment

### Build & Package

From project root:

```bash
make clean package
```

For rootless packaging/deploy (example):

```bash
make clean do FINALPACKAGE=1 STRIP=0 THEOS_PACKAGE_SCHEME=rootless THEOS_DEVICE_IP=<device-ip>
```

Core build configuration:

- [`Makefile`](Makefile)
  - `ARCHS = arm64 arm64e`
  - `TARGET = iphone:clang:16.5:14.5`
  - `INSTALL_TARGET_PROCESSES = SpringBoard`
- [`Tweak/Makefile`](Tweak/Makefile)
- [`Preferences/Makefile`](Preferences/Makefile)

## Project Layout

- [`Tweak/Jikan.x`](Tweak/Jikan.x): Logos hooks and lock screen integration lifecycle
- [`Tweak/JikanPlatterView/JikanPlatterView.m`](Tweak/JikanPlatterView/JikanPlatterView.m): platter UI, styling, timers, update handling
- [`Tweak/TT100/TT100.m`](Tweak/TT100/TT100.m): battery sampling + refresh pipeline
- [`Tweak/TT100/TT100Database.m`](Tweak/TT100/TT100Database.m): sqlite-backed charge history/statistics
- [`Preferences/Resources/Root.plist`](Preferences/Resources/Root.plist): preference specifiers