# LaunchDeck

LaunchDeck is a native macOS launcher app that aims to recreate and extend the classic Launchpad experience.

## Structure

- `Package.swift`: Swift Package entry for opening and building the app in Xcode.
- `Sources/LaunchDeck/`: app source code.
- `docs/launchdeck-spec.md`: product scope, technical design, and iteration roadmap.

## Display Target

LaunchDeck chooses its launch display from the `LAUNCHDECK_DISPLAY` environment variable.

In `DEBUG` builds, if the variable is not set, LaunchDeck defaults to display index `1` so development runs stay on a stable screen. If only one display exists, it falls back safely.

- unset or `cursor`: open on the display containing the mouse pointer
- `primary`: open on the first macOS display
- `main`: follow `NSScreen.main`
- `0`, `1`, `2`, ...: open on a specific display index from `NSScreen.screens`

In Xcode, set this under `Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables`.
