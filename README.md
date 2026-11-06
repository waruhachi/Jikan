<p align="center">
  <img src="Resources/Banner.png" alt="Jikan charging estimates in Classic and Progress Ring styles" width="100%" />
</p>

<h1 align="center">Jikan</h1>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-1.2.0-0a84ff?style=for-the-badge" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%2014.0%E2%80%9326.0.1-111111?style=for-the-badge" />
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPLv3-blue?style=for-the-badge" /></a>
  <img alt="Language" src="https://img.shields.io/badge/language-Objective--C%20%26%20Logos-2b2b2b?style=for-the-badge" />
  <a href="https://havoc.app/package/jikan"><img src="https://img.shields.io/badge/available_on-Havoc-1757FF?style=for-the-badge" alt="Available on Havoc" /></a>
</p>

## About

Jikan puts a charging estimate on your Lock Screen. Set the percentage you want to reach and see how much time is left. Choose a pill you can tap for more battery readings, or a compact estimate beside the date.

## Pill or date row

The Classic pill shows your remaining time with a charging indicator. Progress Ring shows the estimate alongside a circular display of your progress toward the selected target. You can preview both styles in Settings.

On iOS 16 or later, **Use Date Row Instead** places an estimate such as "27m to 80%" alongside the date. It also works with an existing inline widget.

## Charging estimates

Apple is the initial default and is recommended after Jikan confirms measured inputs. Devices with consistently unavailable inputs automatically use Jikan; a previously confirmed Apple recommendation survives temporary missing readings. You can select either algorithm yourself. The existing estimated-power warning is shown only after measured inputs have been confirmed unavailable. Apple uses reconstructed charging models based on Apple's iOS 26 estimator, with targets of 80%, 85%, 90%, 95%, and 100%.

The Jikan algorithm uses your device's charging history and current battery readings. It supports any whole percentage from 1% to 100%.

Both calculate estimates on your device. The target sets the percentage Jikan estimates toward; it doesn't change your phone's charging limit.

Read [how Jikan estimates charging time](docs/charging-estimates.md), including both algorithms and the reverse engineering behind Apple mode.

## Build your Stack

Estimated Time is always included and follows the main target in Settings. Add estimates for other charge targets, wattage, battery temperature, or battery voltage, then arrange the optional readings in your preferred order. Tap the pill to cycle through them.

When the displayed estimate reaches its target, the pill advances to the next higher unfinished target. Other readings stay selected, and completed targets remain available when cycling manually. The pill stays available while a higher target remains unfinished. The date-row estimate and target notification continue to follow the main target.

## Appearance and placement

- Turn Jikan on or off in Settings; the change takes effect immediately.
- Drag the pill in the Lock Screen preview or position it with sliders. Portrait and landscape positions are saved separately.
- Lock horizontal or vertical movement while adjusting its position.
- Adjust the background opacity, with Liquid Glass on supported systems.
- Preview the pill styles in Settings with your system's light or dark appearance.
- Use your system's temperature unit or choose Celsius or Fahrenheit.
- See a yellow charging indicator when charging is slow.
- Keep the charged state visible after reaching your selected percentage.
- Hide the Lock Screen quick action buttons always or only while charging.
- Hide the Focus and notification count text, which can overlap the pill, always or only while charging.
- Hide the swipe to unlock text always or only while charging.

## ChargeLimiter integration

If you use [ChargeLimiter](https://havoc.app/package/chargelimiter), set your charge limit there and tap **Sync with ChargeLimiter** in Jikan. It imports the limit as your estimate target, so you only have to enter the percentage once.

Tap Sync again whenever you change your limit. For limits outside Apple's presets, choose the Jikan algorithm.

## Localization and open source

Jikan includes English, German, Swedish, Turkish, and Vietnamese. Translations are managed on [Crowdin](https://crowdin.com/project/jikan), where you can improve an existing translation or request a new language without using Git.

Jikan is open source under the [GNU GPLv3 license](LICENSE). You can explore the code, contribute improvements, or [report an issue](https://github.com/waruhachi/Jikan/issues).

## Support development

If you'd like to support me and Jikan's development, you can buy it on [Havoc](https://havoc.app/package/jikan). **The paid and free versions will always have the same features and functionality, with no paid-exclusive features.**

## Screenshots

<p align="center">
  <img src="Resources/LockScreen.png" alt="Charging estimates on the Lock Screen, in a pill or beside the date" width="49%" />
  <img src="Resources/Pill.png" alt="Jikan pill styles and the Pill Style preferences" width="49%" />
</p>

<p align="center">
  <img src="Resources/Battery.png" alt="Live battery wattage, temperature, and voltage" width="49%" />
  <img src="Resources/Position.png" alt="Portrait and landscape pill placement and position preferences" width="49%" />
</p>
