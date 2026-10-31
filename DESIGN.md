# Solo Island interface

## Scope

The 0.6.1 redesign preserves the user's dark plum, mint and violet tones and the
behavior in PRODUCT.md. This is a compact native macOS working surface.

## Palette

| Role | Value |
| --- | --- |
| Background | `#100B18` |
| Navigation | `#171020` |
| Content surface | `#1D1528` |
| Raised control | `#291F36` |
| Text | `#F5F1FA` |
| Secondary | `#B7ABC6` |
| Muted | `#9C8EAD` |
| Mint | `#86E6C5` |
| Lavender | `#BAA4F5` |
| Destructive | `#F590AF` |

Color signals selection, playback, progress and actual state. Solid controls
replace repeated mint-purple gradients; a restrained plum wash identifies the
shell. No fabricated artwork, audio analysis, status or metrics.

## Structure

A short brand/status line sits above a full-width workspace. The vertical rail is
removed. Five labeled destinations form a lower dock; settings, pin and quit are
separate fixed-position controls at its right. Command-1…5 selects a destination;
Command-comma opens settings. Pressing pin does not shift neighboring controls.
Music puts artwork and metadata beside transport, with a shared seek rail below.
Focus puts its HH:MM ring beside the task and pause action; completion and Focus
automation sit on a separate lower line. Other sections inherit the full width.

A separate, passive black window sits flush with the screen edge around the
camera. Its central gap uses the measured cutout plus 16 pt; each side is 72 pt.
It never becomes key and never captures clicks. The main panel continues to hide
on exit; the wings remain while a track or focus session exists. No activity hides
both windows. Hovering either wing reveals the main panel, including the first
hover after a Space/display switch.

Music: actual artwork/provider icon on the left; three playback-state bars on the
right. Pausing retains the small indicator but stops motion. These are a state
animation driven by the playback clock and track identity, not audio metering or
beat detection. No microphone, system audio or screen capture is requested.
Focus: actual-progress timer icon on the left and HH:MM on the right. When both
activities exist, time stays visible beside a smaller music indicator. Paused
focus uses lavender. Reduce Motion and sleeping displays stop bar updates.

## Type, states and motion

SF system typography: 20–26 pt titles, 12–14 pt content, 10–11 pt supporting text.
Monospaced digits are for actual time and values. Continuous corners: 16 pt content
surfaces and 11–13 pt controls, inside the user-controlled outer window shape.
Press feedback is about 130 ms. Playback motion pauses when paused, hidden or
under Reduce Motion. Keyboard focus, disabled and error states stay visible.
Primary-button text adapts to accent luminance.

## Verification

Review real native music, tasks, focus, clipboard, actions, onboarding and settings
captures together. Check narrow width, long titles, states, camera clearance and
HH:MM timers. Preserve the native input, Space-hover and quit checks. Generated
motion assets remain outside Git.

## Skill inputs

Impeccable's local Operate/craft guidance and UI/UX Pro Max's SwiftUI data inform
the design. The remote Impeccable concept catalog was unavailable: its local seed
`seed:3e2a7d757c773901` was degraded, not a catalog-backed selection or an approved
image comp. User-confirmed palette and native constraints govern the work.
