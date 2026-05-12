# Plan

Build a small personal-use macOS menu bar app that starts a sleep timer, gradually lowers built-in display brightness and system output volume, then puts the Mac into full sleep when the timer ends. The MVP should be native, minimal, and reliable on the latest macOS, with duration and floor settings kept simple enough to ship quickly.

## Scope
- In: Native macOS menu bar app, default one-click 30 minute timer, selectable durations of 30/45/60/90/120 minutes, gradual linear brightness fade, gradual linear volume fade, configurable brightness/volume floor, built-in display support, active/inactive menu bar icon state, right-click options menu, full system sleep at timer end.
- Out: App Store distribution, notarized public release, external display support, restore-on-cancel behavior, sleep warning notification, screen warmth shift, Raycast integration.

## Action items
[ ] Create a native macOS app shell using SwiftUI plus AppKit where needed, likely with an `NSStatusItem` so left-click starts the default timer while idle and cancels the running timer while active.
[ ] Add timer state management for idle/running/canceling/completed states, including default duration persistence, second-click cancel behavior, and the fixed MVP duration choices: 30, 45, 60, 90, and 120 minutes.
[ ] Implement the menu bar UI with a right-click options menu, duration submenu, cancel action, and settings for default duration plus brightness and volume floor values.
[ ] Add active/inactive icon styling so the menu bar icon is light gray or transparent while idle and white while a timer is running.
[ ] Implement volume control using the most reliable personal-use path first, either native CoreAudio APIs or macOS scripting commands if they prove simpler and more stable.
[ ] Implement built-in display brightness control using IOKit/CoreDisplay-style APIs or a small helper command-line tool if direct native control is unreliable on the latest macOS.
[ ] Implement the fade engine so brightness and volume linearly interpolate from their current values down to the configured floors over the selected timer duration, with periodic updates that avoid visible stepping.
[ ] Implement full system sleep at timer completion using a reliable system command path such as `pmset sleepnow` or the equivalent Apple event flow, then verify it works without extra prompts on the target Mac.
[ ] Persist settings locally with `UserDefaults`, including default timer length, brightness floor, and volume floor, with `0` as the default floor for both.
[ ] Validate edge cases: cancel mid-timer does not restore brightness/volume, starting a new timer replaces or rejects the old one cleanly, sleep still runs when the menu is closed, and invalid brightness/volume values are clamped.
[ ] Build and manually test on the latest macOS with short debug timer durations before testing the full 30 minute flow.

## Later phases
[ ] Add a non-audio notification around 1 minute before sleep.
[ ] Add a fade curve setting with `Linear` as the MVP default and a later `Late fade` option, internally modeled as an ease-in or accelerating curve.
[ ] Add screen warmth adjustment if a reliable and acceptable macOS control path exists.
[ ] Add Raycast integration through a script command, URL scheme, or lightweight CLI entry point.
[ ] Add support for external displays if a reliable per-display brightness path is available.
[ ] Add optional restore-on-cancel behavior if it becomes useful after real use.
