# LaunchDeck Spec

## Positioning

LaunchDeck is a native macOS launcher app that targets a high-fidelity recreation of the classic macOS Launchpad:

- fullscreen-first presentation
- paged icon grid
- folders
- app search
- drag-oriented organization

The long-term goal is to rebuild the old Launchpad interaction model first, then extend it carefully without losing that system-like feel.

## Project Layout

- `LaunchDeck/` is the standalone project root.
- `LaunchDeck/Sources/LaunchDeck/` stores the app source code.
- `LaunchDeck/docs/` stores product and engineering documents.

## Product Goals

1. Recreate the classic Launchpad look and feel on modern macOS as closely as practical.
2. Keep the launcher fast enough to feel system-native.
3. Make organization user-controlled instead of opaque or system-managed.
4. Leave room for an optional advanced integration track later:
   private APIs, Dock replacement research, and migration tooling.

## Current Iteration

The current iteration focuses on a legacy-Launchpad visual and interaction baseline, still delivered as a standalone app.

### Implemented in this round

- SwiftUI macOS app scaffold under the project root
- installed app discovery from common application directories
- fixed paged grid closer to classic Launchpad density
- top-centered lightweight search field
- wallpaper-backed launcher surface
- icon-first presentation without dashboard chrome
- folder-capable data model
- centered folder presentation closer to classic Launchpad
- adaptive page layout based on screen size
- directional page transitions
- window-level open/close animation
- trackpad horizontal paging monitor
- long-press edit mode entry
- icon jiggle during edit mode
- drag reorder on the top-level grid
- drag app onto app to create a folder
- drag app onto folder to merge it
- click to launch real apps
- AppKit-backed pager with continuous page motion
- shared interaction engine for page position and folder presentation progress
- AppKit pan gesture wiring for direct page dragging
- continuous page-dot response driven by live page position
- geometry-based folder open/close transition state

### Deferred to later iterations

- persistent layout storage
- custom folder creation/editing
- fullscreen overlay window manager behavior
- global hotkey and login item helper
- import from historical Launchpad layouts
- multi-display orchestration
- private Dock integration experiments

## Core User Flows

### Open launcher

1. User starts LaunchDeck.
2. Launcher loads installed apps.
3. User sees a fullscreen icon grid with bottom page dots and minimal chrome.

### Search

1. User types in the top search field.
2. Grid narrows to matching apps and folders while keeping the Launchpad visual language.
3. If a folder matches, the folder remains visible and its content can still be opened.

### Open app

1. User clicks an app tile.
2. LaunchDeck calls `NSWorkspace` to open the app bundle.

### Open folder

1. User clicks a folder tile.
2. A centered folder surface opens over the launcher.
3. User can launch any app inside the folder.

## Technical Design

### App shell

- Frameworks: `SwiftUI`, `AppKit`, `Foundation`
- Packaging: Swift Package executable so the project opens cleanly in Xcode and stays lightweight for early iteration
- Window style: hidden-title launcher surface
- Visual target: legacy Launchpad, not a generic dashboard

### Data model

`LaunchItem`

- `app`
- `folder`

Fields:

- stable UUID for UI identity
- title
- subtitle
- bundle URL for real apps
- children for folders

This model is intentionally independent from any private Apple Launchpad schema. That keeps the standalone app viable even if we later build migration tooling from legacy sources.

### App discovery

The current scanner searches:

- `/Applications`
- `/System/Applications`
- `/System/Applications/Utilities`
- `~/Applications`

Rules:

- include `.app` bundles
- skip hidden files
- deduplicate by standardized path
- sort alphabetically

### Initial foldering strategy

The prototype auto-builds a few practical folders from discovered apps:

- Browsers
- Developer
- Utilities

Everything else stays as top-level apps.

This is only a bootstrap heuristic. User-defined folders will replace it once persistence and drag/drop land.

### Pagination

- adaptive page size from the active screen layout
- page selection state in the store
- AppKit-managed pager surface for continuous horizontal movement
- live page position shared into the SwiftUI shell through `LaunchpadInteractionEngine`
- search resets back to page 1

Later work can shift to stronger fullscreen choreography, keyboard traversal, and drag-across-page behavior.

### Visual fidelity baseline

The app should feel close to the old system Launchpad in these areas:

- full-window launcher surface instead of a dashboard card
- wallpaper-derived blurred background
- icon-first grid with labels underneath
- screen-size-aware icon density and spacing
- centered search field with low visual weight
- no management header, counters, or reload chrome
- folder surface that opens over the page instead of a conventional modal panel

### Launching

Apps are opened through `NSWorkspace.OpenConfiguration`.

No private APIs are required for the standalone track.

### State management

`LaunchDeckStore` is a `@MainActor` `ObservableObject`.

Responsibilities:

- load catalog
- group apps into initial folders
- manage pagination
- manage search query
- hold selected folder state
- surface launch errors

`LaunchpadInteractionEngine` is a separate `@MainActor` interaction layer.

Responsibilities:

- track continuous page position during AppKit gesture handling
- provide page-dot interpolation values
- coordinate folder presentation geometry and timing
- isolate transient interaction state from catalog/state persistence

## Iteration Roadmap

### Milestone 1: Standalone Launchpad baseline

- app scanning
- Launchpad-like paged grid
- search
- folder presentation
- real app launching

### Milestone 2: User organization

- persistent order
- drag reorder
- folder create/rename/delete
- hide app support
- pinned favorites row

### Milestone 3: Feels like Launchpad

- fullscreen presentation controller
- animated open/close transitions
- keyboard navigation
- edit mode icon jiggle
- drag into folder and drag across pages
- hot corners and global shortcut helper
- login item

### Milestone 4: Migration and power features

- import legacy ordering if recoverable
- category rules
- recent apps
- custom sections
- multi-display awareness

### Milestone 5: Experimental system integration

- research replacing or shadowing Dock entry points
- evaluate private API hooks
- evaluate Dock injection feasibility under reduced system security

This milestone is intentionally isolated from the main app so the stable product remains usable without hack-level system changes.

## Risks

### Functional

- system app scanning may surface too many apps without manual curation
- folder heuristics can feel arbitrary before persistence exists
- the current visual baseline is closer to old Launchpad, but editing behavior is still partial

### Technical

- fullscreen overlay behavior on macOS needs AppKit window control, not just plain SwiftUI
- drag/drop folder editing will require careful hit-testing and model diffing
- true Dock replacement is not part of the stable track and must remain isolated

## Next Development Priorities

1. Replace SwiftUI tile drag/drop with an AppKit-backed interaction surface for cross-page dragging.
2. Persist layout to a local store.
3. Add native-style folder expansion/collapse choreography tied to source tile geometry.
4. Promote the window into a stronger launcher-style presentation controller.
