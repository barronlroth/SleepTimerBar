# SleepTimerBar

Tiny personal macOS menu bar sleep timer.

## Behavior

- Left-click the menu bar icon to start the default timer.
- Left-click again while active to cancel the timer.
- Right-click the icon to open options.
- Choose a timer duration: 30, 45, 60, 90, or 120 minutes.
- Configure the default duration, brightness floor, and volume floor.
- Brightness and volume fade linearly from their current values to the configured floors.
- Raising brightness or volume during a session resumes that channel's fade from the new level over the remaining time. The sleep deadline stays the same. Changes within 1.5 percentage points are treated as rounding noise.
- Lowering a channel below its configured floor keeps it at the lower level.
- Canceling leaves brightness and volume at their current levels.
- Manual sleep, lid closure, or other system sleep cancels the timer; waking does not resume it.
- The icon stays icon-only. Hover for an updated countdown, or open the options menu for the countdown and estimated sleep time.
- Brightness/volume failures appear in the options menu, with details on hover. The affected channel stops fading for that session; the timer and other channel continue. Starting a new timer retries both channels.
- When the timer completes, the app requests full system sleep even if a fade channel failed. Sleep-command failures also appear in the menu.
- Elapsed time uses a monotonic clock, so changing the system clock does not alter the timer's duration.
- Volume and sleep commands run asynchronously with a three-second timeout and are canceled with their session. Unchanged rounded volume levels skip redundant writes.

Brightness control uses the macOS private DisplayServices framework and supports active built-in displays only. If no built-in display is active, brightness fading is unavailable; volume fading and the sleep timer still work.

## Run

Use the Codex Run action, or run:

```sh
./script/build_and_run.sh
```

The script builds a local app bundle at `dist.noindex/SleepTimerBar.app` and launches that bundle as a menu bar app.

## Tests

```sh
swift test
```

The tests use a fake clock, scheduler, and hardware controllers to check timer completion, cancellation, sleep/wake behavior, manual adjustments, and failure paths without changing real brightness or volume or putting the Mac to sleep. Separate helper-process tests cover output capture, command failures, timeouts, and cancellation.
