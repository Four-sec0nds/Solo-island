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

## Top-edge reveal and agents (0.7.0)

The full panel touches the top edge at its final width and reveals vertically.
Content still starts below the physical camera clearance. The narrow-neck
attachment is removed. Every compact activity indicator hides before reveal and
stays hidden until collapse completes, including when an animation is interrupted.

Agents have a header entry (⌘6), leaving the five bottom destinations intact.
The operational view shows real project/session state and hours/minutes elapsed.
Permission requests show their complete tool input and project path before an
explicit one-shot allow, deny or return-to-client choice. Permission requests
take priority over focus/music in compact mode; no spinning or false progress.
The connection screen distinguishes installed hooks from actually received events.

## Compact player and agent pets (0.7.1)

Default width is 560 points, adjustable between 520 and 680. The body is 360
points tall with camera clearance added above it. Previous large saved widths
migrate once to the compact default; later user choices persist. Keep original
text sizes readable: reduce cover/ring size and spacing, and scroll long forms.
All six destinations, including Agents (⌘6), sit in the bottom navigation.

The music card always contains a prominent 7-point seek rail and visible thumb.
Known duration enables absolute seeking even when elapsedTime is missing. When
duration is unavailable the disabled timeline explains the missing metadata.
Web music also reads the service's standard Media Session position state.

Claude Code has an orange eight-legged pixel spider; Codex has Byte, a mint
robot cat. These original sprites are drawn by the native Canvas, with no
external assets. They appear in connections, sessions, permission requests and
the compact camera wing. Working/waiting animates their feet/eyes; hidden panels
and Reduce Motion freeze the animation. Existing bridge decisions stay intact.

## Bounded workspace and downloaded pets (0.7.2)

The header now lives in the top band beside the camera. The center has an
explicit clear hardware gap; both side groups stay in their own safe wing. A
GeometryReader bounds the content before the fixed-size bottom navigation is
measured, so an intrinsic empty-state height cannot push the dock out of the
window. Empty Tasks has a smaller horizontal state within its own scroll area.
Native captures assert dock bounds on every tab, including empty tasks at 520.

Both hand-drawn pets are replaced with downloaded, unmodified community sprite
atlases from xiangking/agent-pet, pinned in Resources/AgentPets/NOTICE.md with
MIT attribution. Claude uses Clawd; Codex uses the blue terminal companion.
Idle/work/wait cells are cropped locally and frozen offscreen/with Reduce Motion.
Music wings are visible only during playback; pause/stop hides cover and bars.
Independent focus and agent indicators retain their own activity rules.

## Fitted workspaces and web agents (0.8.0)

All compact destinations use fitted controls and visible page buttons. Tasks,
focus choices, shelf entries, quick actions and agent sessions use bounded
pages; settings use five section tabs. Deadline/calendar views have compact
rows. Long shelf text and complete tool input are measured into pages without
dropping characters. No primary island surface relies on a scroll gesture.
Native validation scopes control rectangles to their actual host so every
interactive element must stay above the fixed dock and inside the panel.

Music login is a full-size, resizable native window with the same WKWebView
and data store. The small island never hosts an unusably small login form.
Web agents use dedicated browser windows or the bundled Chromium extension.
The existing agent pets represent these sessions too, with an explicit web
label. Only lifecycle state crosses the local bridge; webpage changes and
unsupported/cloud-only states remain a capability limit.

## Web activity and add controls (0.8.1)

All icon-only add buttons share one 18-point icon frame and the existing filled
button style. Web connection rows report observer installation and received
events. Opening a provider returns to activity instead of keeping the connection
page selected. The production observer starts before page scripts and tracks
existing request/stream lifecycles and Codex task status fields. Native checks
exercise that actual script and the site consumer, rather than injecting events.
