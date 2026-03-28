# MaelstromTracker

MaelstromTracker is a World of Warcraft addon for **Shaman** that tracks **Maelstrom Weapon** stacks and provides a configurable **weapon imbue / shield reminder** system for Midnight (12.x).

## Current Version

- **Version:** `1.0`
- **Interface:** `120001`

Version and interface are defined in `MaelstromTracker.toc`.

## What the Addon Does

### 1. Maelstrom Weapon Main Bar

- Tracks `Maelstrom Weapon` stacks (0-10) in real time.
- Segment-based bar with stack text and optional glow at 10 stacks.
- Optional "show only in combat" behavior.
- Movable frame with lock/unlock support.
- Configurable size, colors, border, and shadow styling.

### 2. Strict Class/Spec Gating

The addon is active only when all of the following are true:

- Class is **Shaman**
- Specialization is **Enhancement** or **Elemental**

If not in a supported context, the addon hides UI and skips runtime updates.

### 3. Weapon Imbuements Tracker

The addon can show warning icons when required buffs/imbues are missing or low:

- `Windfury Weapon`
- `Flametongue Weapon`
- `Lightning Shield`
- `Earth Shield` (self-only, when Therazane's Resilience path is active)

Behavior notes:

- If `Instinctive Imbuements` is active, tracker focuses on Lightning Shield missing-state behavior.
- Otherwise, warnings are based on missing state and configured time threshold.

### 4. Midnight Reliability/Trust Model

To reduce false positives caused by restricted aura access or transition timing:

- The tracker uses a trust state and grace window after transitions.
- During untrusted states, warnings are hidden by default.
- Trust is restored after successful fresh reads.
- Debouncing is applied to warning display to reduce flicker.

### 5. Situations Where Imbue Warnings Are Suppressed

Imbue reminders are intentionally hidden when:

- In combat (restricted aura scenarios)
- In Mythic+ (`Challenge Mode`) runs
- In sanctuary zones (if sanctuary-hide option is enabled)
- In unsupported class/spec contexts

### 6. Options UI

In the in-game AddOn options panel (`MaelstromTracker`), you can configure:

- Main bar lock, combat-only mode, stack text, glow
- Main bar width/height
- Text/bar colors
- Border/shadow toggles, thickness, padding, and colors
- Imbue tracker enable/lock
- Imbue icon size
- Warn threshold (seconds)
- Trust grace seconds
- Hide warnings when state is untrusted
- Hide warnings in sanctuary zones

### 7. Slash Commands

- `/maelstromtracker`
- `/mt`

Opens the addon settings panel.

## Files

- `MaelstromTracker.lua` - core runtime logic
- `Options.lua` - settings UI
- `MaelstromTracker.toc` - addon metadata/version

## Installation

1. Place the `MaelstromTracker` folder in your WoW AddOns directory:
   - `World of Warcraft/_retail_/Interface/AddOns/`
2. Ensure the folder contains the three files listed above.
3. Launch/reload the game and enable **MaelstromTracker**.

## Notes

- Designed around Midnight-safe aura access patterns.
- If Blizzard API behavior changes in future patches, reminder reliability logic may need adjustment.
