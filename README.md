# SleepTimerBar

Tiny personal macOS menu bar sleep timer.

## MVP behavior

- Left-click the menu bar icon to start the default timer.
- Left-click again while active to cancel the timer.
- Right-click the icon to open options.
- Choose a timer duration: 30, 45, 60, 90, or 120 minutes.
- Configure the default duration, brightness floor, and volume floor.
- Brightness and volume fade linearly from their current values to the configured floors.
- When the timer completes, the app runs full system sleep.

## Run

Use the Codex Run action, or run:

```sh
./script/build_and_run.sh
```

The script builds a local app bundle at `dist/SleepTimerBar.app` and launches that bundle as a menu bar app.
