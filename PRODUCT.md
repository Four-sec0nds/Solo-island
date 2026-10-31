# Solo Island

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS desktop, not a website or mobile wrapper. The design tool's mobile
platform presets do not replace AppKit conventions.

## Stack

SwiftUI and AppKit, macOS 14+, Apple Silicon. IslandCore is independently tested.

## Users and Purpose

Mac users keep music, their own tasks, focus sessions, clipboard items and quick
actions close while working in other apps. The interface is Russian. The product
is presented as part of Planify; this is a brand relationship, not task syncing.

## Mechanism and Operating Context

A compact panel grows from the physical camera cutout on hover. The full panel collapses after the cursor leaves. With no activity it is invisible;
while music or focus exists, only small indicators beside the camera remain. Pinning keeps it open; an expanded
island remains above other windows, including fullscreen Spaces. A power button
fully quits the app. Re-entering after changing Space/display must remain prompt.

## Capabilities and Constraints

- Music: real system metadata and an optional embedded provider website. Preserve
  play/pause, previous/next, seek, service selection, browser fallback and login.
- Tasks are independent of Calendar. Preserve deadlines, a date slider, reminder
  calendar and notifications a day and an hour before a deadline.
- Focus supports presets, custom hours/minutes, pause/resume and task completion.
  Focus time always displays HH:MM without wrapping or seconds.
- Clipboard retains files, text and screenshots. Preserve previews, filters,
  copying, pinning, drag/drop and the last-five-unpinned-files policy.
- Quick actions run actual apps, folders and Shortcuts and show their real icons.
- Settings retain width, corner radius, reveal timing, artwork accent, providers,
  notification permission and explicit user-configured Focus Shortcuts.
- No account backend, fabricated player capabilities or new service credentials.
- Normal dimensions stay compact; header content clears the physical camera.
  Preserve existing user data, key actions, keyboard behavior and Reduce Motion.
- A full-width workspace and bottom navigation replace the left panel. The palette
  remains unchanged. Music/focus wings must not steal keyboard focus or clicks.

## Brand Commitments

The user requests a new, noticeably modern design in approximately the existing
tones: dark plum with mint and lavender/violet accents, soft continuous corners
and a calm dark background. Solo Island's name and orbit/capsule identity remain.
These constraints and the established features are confirmed in the conversation;
the redesign changes presentation, not the product's function.

## Evidence on Hand

The implementation and verified native 0.5.4 captures in the artifact branch
`solo-island-builds` are the baseline. Local `dist/` copies are generated examples,
not user data. Track artwork, metadata and application icons come from real sources;
preview fixtures are explicitly synthetic. There are no paid-plan, audio-quality,
testimonials, performance or cloud-sync claims to add to the UI.

## Product Principles

- Make the next action obvious within the small panel.
- Keep navigation stable and preserve familiar native controls and keyboard access.
- Treat personal clipboard and task content as the main content, not decoration.
- Make interaction feedback fast, coherent and optional under Reduce Motion.
- Keep the camera-cutout connection and unobstructed hit areas functional.
