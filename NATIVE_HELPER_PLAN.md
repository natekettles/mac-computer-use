# Computer Use Native Helper Plan

Last updated: 2026-04-18

## Goal

Replace the fragile CLI `osascript` action path with a native macOS helper that can provide a Codex-like Computer Use experience:

- app-aware screenshots
- accessibility-tree inspection
- smoother and less disruptive action execution
- overlay automation cursor
- focus save/restore when input requires foreground delivery

This document is the implementation plan for the next stage of the clone.

## High-Level Architecture

Split the system into two layers:

1. `MCP server`
   - stays small and protocol-focused
   - validates tool arguments
   - maps tool calls to helper IPC requests
   - normalizes helper responses into `ComputerUseToolResult`

2. `Native helper`
   - owns all macOS-specific capabilities
   - stable app/binary identity for permissions
   - accessibility inspection
   - event synthesis
   - screenshot capture
   - window enumeration and bounds lookup
   - overlay cursor rendering
   - focus save/restore

Recommended implementation language:

- Swift

Recommended helper shape:

- a small `.app` bundle or signed helper binary with a stable bundle identifier
- launched locally by the MCP server
- communicates over local IPC

## Responsibilities

### MCP server responsibilities

- expose the cloned tool names:
  - `list_apps`
  - `get_app_state`
  - `click`
  - `drag`
  - `type_text`
  - `press_key`
  - `set_value`
  - `scroll`
  - `perform_secondary_action`
- validate schemas
- convert MCP requests into helper requests
- convert helper replies into:
  - text content
  - structured content
  - optional screenshot content
- keep the public contract stable even while helper internals change

### Native helper responsibilities

- enumerate running apps and windows
- inspect accessibility elements
- capture screenshots
- perform pointer and keyboard actions
- draw the automation cursor overlay
- restore previous focus after transient activations
- maintain a short-lived action session context

## Permission Model

The native helper should be the permissioned actor for:

- Accessibility
- Screen Recording / Screen & System Audio Recording
- Automation if needed

This avoids the current attribution problem where `osascript` becomes the effective blocked actor instead of our actual app.

## IPC Shape

Prefer a minimal JSON protocol over one of:

- stdio
- local Unix domain socket
- XPC if you want a deeper macOS-native design

For speed of implementation, start with:

- helper launched as a subprocess
- newline-delimited JSON messages over stdio

Example request:

```json
{
  "id": "req_123",
  "method": "click",
  "params": {
    "app": "com.apple.calculator",
    "x": 320,
    "y": 620
  }
}
```

Example response:

```json
{
  "id": "req_123",
  "ok": true,
  "result": {
    "toolName": "click",
    "app": {
      "bundleId": "com.apple.calculator",
      "name": "Calculator"
    },
    "snapshot": {
      "windowTitle": "Calculette",
      "treeText": "App=com.apple.calculator\\nWindow: \"Calculette\", App: Calculator.",
      "elements": []
    },
    "artifacts": {
      "screenshotMimeType": "image/png",
      "screenshotBase64": "<...>"
    }
  }
}
```

## Overlay Cursor

### Purpose

Provide the Codex-like “second cursor” UX without moving the visible hardware cursor in the normal user-facing way.

### Behavior

- borderless transparent window
- always on top
- does not accept mouse events
- spans either:
  - the target display
  - or all displays
- draws a translucent custom cursor glyph
- animates between points smoothly

### Visual spec

First-pass target:

- white cursor body
- slight shadow
- opacity around `0.75–0.9`
- scale around `1.1x` relative to standard pointer
- click pulse:
  - brief scale down
  - subtle ring or glow

### Motion spec

- interpolate movement over `120–250ms`
- ease-out curve
- optional small lag/trail effect

### Important implementation note

The overlay cursor should be independent from the real pointer location.

That gives us:

- smoother perceived automation
- no requirement to visibly drag the actual system cursor
- lower disruption to the user experience

## Focus Strategy

### Working assumption

Based on the bundled implementation behavior:

- some actions can happen without obvious foreground takeover
- `type_text` likely still requires a short focus handoff or equivalent routing trick

### Modes

Implement two execution modes:

1. `background-safe`
   - AX reads
   - window enumeration
   - screenshots
   - some direct AX element actions
   - `set_value` when an element is settable

2. `interactive`
   - real click
   - drag
   - keyboard input
   - temporary app activation may be required

### Focus choreography

When an interactive action requires focus:

1. capture current frontmost app/window
2. move overlay cursor toward target
3. activate target app/window if needed
4. perform action
5. capture post-action state
6. restore previous frontmost app/window when safe

This should be fast enough that the user sees at most a brief flicker or “glitch,” similar to bundled Codex behavior.

## Screenshot Strategy

### Current issue

The current CLI backend uses full-screen `screencapture`.

That is too primitive for Codex-like behavior.

### Target strategy

The helper should become window-aware:

1. identify target window bounds
2. capture the display
3. crop to target window bounds when appropriate
4. optionally keep both:
   - full-screen source
   - window-focused crop

### Why this matters

- lets the model reason about a specific app while the user keeps working elsewhere
- matches the observed “background” feel better
- reduces noise in returned screenshots

## Accessibility Tree Strategy

### Current state

The clone currently returns only minimal window text.

### Target state

Use AX APIs to build a tree with:

- stable per-snapshot element indices
- role
- description
- help text
- value
- settable/enabled flags
- supported actions
- child hierarchy

### Rendering rule

Keep two representations:

1. structured tree
2. Codex-like rendered `treeText`

The structured tree is for machine use.
The rendered tree is for human/debug parity.

## Tool Implementation Strategy

### `list_apps`

Use:

- `NSWorkspace`
- Accessibility/process metadata where useful

Target output:

- running apps first
- later add recent-app history if desired

### `get_app_state`

Use:

- target app resolution
- focused/target window lookup
- AX tree extraction
- app/window screenshot capture

Return:

- app metadata
- window title
- tree text
- structured elements
- screenshot artifact

### `click`

Phase 1:

- coordinate click
- overlay cursor animation
- CGEvent mouse down/up

Phase 2:

- element-index click by resolving the indexed AX element to screen coordinates or AX action

### `drag`

Use:

- animated overlay cursor path
- CGEvent drag sequence

### `press_key`

Use:

- temporary focus handoff if needed
- CGEvent keyboard sequence
- focus restore

### `type_text`

Preferred strategy:

1. if target element is directly settable and known:
   - use AX value setting
2. otherwise:
   - focus target briefly
   - synthesize keyboard events
   - restore previous focus

This gives better background behavior than always using keystrokes.

### `set_value`

Use:

- direct AX value update

This is one of the most valuable background-safe primitives.

### `scroll`

Use one of:

- AX scroll action if available
- wheel event synthesis targeted at window coordinates

### `perform_secondary_action`

Use:

- AX action invocation on target element

This should stay app-aware and not necessarily require full app activation.

## Internal Data Model

The helper should keep a short-lived session state:

- `frontmostAppBeforeAction`
- `frontmostWindowBeforeAction`
- `targetApp`
- `targetWindow`
- `lastSnapshot`
- `lastIndexedElements`

This enables:

- element-index actions after `get_app_state`
- focus restoration
- post-action refresh

## Recommended Rollout Order

### Phase 1

- native helper skeleton
- IPC transport
- permission checks
- `list_apps`
- `get_app_state` with screenshot + minimal window metadata

### Phase 2

- overlay cursor
- coordinate `click`
- `press_key`
- `type_text`
- focus save/restore

### Phase 3

- AX tree extraction
- element indexing
- `set_value`
- element-index `click`
- `perform_secondary_action`

### Phase 4

- `drag`
- `scroll`
- better window-targeted screenshots
- motion polish and visual polish

## Non-Goals For First Native Version

Do not try to fully clone all Codex behavior immediately:

- no bug-for-bug parity
- no perfect background typing illusion
- no complex multi-display choreography
- no complete approval UX clone

The goal is:

- robust tool execution
- honest focus behavior
- lower disruption than the CLI AppleScript path
- contract compatibility with the MCP surface we already defined

## Immediate Next Step

Create the helper scaffold in `computer-use/` with:

- helper protocol definitions
- a Swift executable or app target
- a `get_app_state` implementation with:
  - app lookup
  - frontmost window metadata
  - screenshot capture
- a simple overlay cursor proof of concept
