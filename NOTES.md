# Computer Use Reverse-Engineering Notes

Last updated: 2026-04-17

## Purpose

This file captures implementation-facing observations that should stay separate from the public clone contract in `SPECS.md`.

## Bundled Plugin Layout

Observed local plugin path:

- `~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750`

Important files:

- `.codex-plugin/plugin.json`
- `.mcp.json`
- `Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`

## Runtime Ownership

Observed healthy runtime shape on this machine:

- `SkyComputerUseClient mcp` is launched as a child of `codex app-server`
- the healthy desktop instance is not launched directly by arbitrary local callers

Observed example:

- `SkyComputerUseClient` PID `24134`
- parent PID `23283`
- parent command: `codex app-server --analytics-default-enabled`

This strongly suggests the MCP surface is brokered by Codex app-server rather than exposed as a simple standalone stdio server contract.

## Binary Strings

Observed relevant strings in `SkyComputerUseClient`:

- `x-codex-turn-metadata`
- `codex.session_id`
- `codex.turn_id`
- `codex.app_session_id`
- `agent-turn-complete`
- `computer_use_mcp_app_approval_requested`
- `computer_use_mcp_app_approval_resolved`
- `computer_use_mcp_approval_result`
- `approvalStore`
- guidance to call `get_app_state` before other actions

Interpretation:

- there is likely out-of-band turn/session context
- approval and session lifecycle are likely first-class internal concepts
- the visible MCP tool API is only part of the full runtime contract

## Service Logs

Observed `SkyComputerUseService` log themes:

- `Codex AppServer Thread Events`
- `Codex thread ended or stopped conversationID=<private>`
- TCC access requests attributed to `com.openai.codex`
- idle timeout and self-termination behavior

Interpretation:

- the service is aware of Codex thread lifecycle
- macOS permissions are mediated in a way that references the Codex host app

## Live Tool Surface Observations

### Shared success shape

Most successful side-effecting tools returned:

- a refreshed textual app/window/accessibility state
- a screenshot

They did not return a simple `"ok"` or boolean-only ack in the rendered surface.

Tools observed with this shape:

- `click`
- `press_key`
- `type_text`
- `drag`
- `scroll`
- `perform_secondary_action`

### Error shape

Observed error outputs were simple text items, for example:

```text
Apple event error -10005: 999999 is an invalid element ID
Accessibility error: AXError.illegalArgument
appNotFound("Calculette")
```

This suggests the clone can start with a straightforward text error surface even if later it also adds structured error metadata.

### Accessibility tree characteristics

Observed `get_app_state` and post-action state snapshots include:

- localized labels
- numeric element indices
- optional metadata inline in text, such as:
  - `ID: ...`
  - `Help: ...`
  - `Description: ...`
  - `Secondary Actions: ...`
  - value-like suffixes for settable elements

The text rendering appears hierarchical and indentation-based.

### User-observed foreground behavior

New observation from live use of the bundled Codex Computer Use implementation:

- when text was entered into Google Chrome through bundled Computer Use, Codex remained visibly focused
- there was a brief visual glitch suggesting Chrome tried to come to the foreground
- focus appeared to return to Codex immediately

Interpretation:

- `type_text` likely does not behave as pure permanent background text injection
- instead, the implementation probably performs a very short activation/focus handoff or equivalent event-routing maneuver
- after input is delivered, focus is restored back to Codex quickly enough that the interaction feels mostly backgrounded

This is consistent with previously observed binary strings:

- `Type literal text using keyboard input`
- `CGEvent`
- `keyboardEventTap`
- `AXFocusedUIElement`
- `AXFocusedWindowChanged`

Working assumption for the clone:

- true text entry should be treated as focus-sensitive
- the realistic target behavior is:
  - save current frontmost app/window
  - briefly activate the target when needed
  - deliver input
  - restore previous focus

### Screenshot model hypothesis

New behavioral hypothesis based on user observation:

- bundled Computer Use appears to do substantial work "in the background"
- that makes full-screen foreground-only screenshots an unlikely sole mechanism

Likely implementation direction:

- screenshots are captured on a per-app or per-window basis when possible
- or the system captures the full display but then resolves app/window-specific state separately through AX/window APIs

Why this matters:

- our current CLI backend uses plain full-screen `screencapture`
- that is probably not sufficient to match the Codex UX
- a higher-fidelity clone should plan for app/window-targeted capture or app/window-aware cropping and composition

Practical implication for the clone architecture:

- the future native helper should own:
  - window enumeration
  - target-window bounds lookup
  - screenshot capture and optional per-window cropping
  - focus save/restore
  - overlay rendering for the automation cursor

### Native helper runtime constraint

New result from the first Swift helper experiments:

- inside the current sandboxed CLI execution context, the helper saw:
  - `NSWorkspace.shared.runningApplications.count == 0`
  - `CGWindowListCopyWindowInfo(...).count == 0`
- outside the sandbox, the same helper immediately saw:
  - real running apps
  - real on-screen windows
  - real window titles and bounds

Interpretation:

- the native helper implementation path is viable
- but desktop visibility depends on running the helper outside the current Codex shell sandbox
- this is not just a logic bug in app discovery; it is a launch-context/runtime restriction

Practical implication:

- for real desktop control, the helper should be treated as a local native sidecar, not as an ordinary sandboxed script
- local validation of native desktop features should be done with unsandboxed launches

### Native click validation

First successful native action result:

- the clone helper now implements coordinate-based `click` using `CGEvent`
- a live unsandboxed test targeted Calculator's delete button coordinates
- bundled Codex Computer Use confirmed the value changed from `123` to `12`

Interpretation:

- direct native event posting works for our clone
- the current implementation is still intentionally minimal:
  - coordinate clicks only
  - no element-index clicks yet
  - no overlay cursor yet
  - no focus restore yet

### Native keyboard validation

Additional successful native action results:

- the clone helper now implements:
  - `press_key` with direct `CGEvent` key posting for common printable keys, modifiers, and basic special keys
  - `type_text` as per-character native key delivery with keycode fallback before unicode fallback
- live validation against Calculator confirmed:
  - `press_key("4")`, `press_key("5")`, and `press_key("Delete")` changed the displayed value in the expected order
  - `type_text("23")` changed the displayed value from `14` to `1423`

Interpretation:

- the native keyboard path is viable
- Calculator accepts the clone helper's native key events when the helper runs unsandboxed
- the minimal focus handoff strategy is already sufficient for this class of app

### Native scroll validation

Additional successful native action result:

- the clone helper now implements app-scoped `scroll` with direct `CGEvent` wheel posting
- the current implementation:
  - activates the target app briefly
  - targets the wheel event at the center of the resolved window
  - restores the previous frontmost app afterward
- live validation against Google Chrome confirmed visible page movement on a long Printful page:
  - a before/after screen capture showed the page content shifted upward after `scroll(direction: "down", pages: 2)`

Interpretation:

- the native scroll path is viable
- targeting the wheel event at the window center is enough for Chrome in this environment
- the current implementation is still intentionally minimal:
  - `element_index` is accepted by the MCP surface but ignored by the helper
  - scrolling is window/app-scoped rather than element-scoped

### Native drag validation

Additional successful native action result:

- the clone helper now implements coordinate-based `drag` with direct `CGEvent` mouse down, drag, and mouse up posting
- live validation against Calculator confirmed actual window movement:
  - initial window bounds: `X=639, Y=226, Width=198, Height=350`
  - after native drag: `X=801, Y=306, Width=198, Height=350`

Interpretation:

- the native drag path is viable
- a short stepped `leftMouseDragged` sequence is sufficient to move a real app window
- like `click`, the current implementation is coordinate-based only

### AX tree and set_value validation

First successful AX-based element result:

- the clone helper now builds a minimal accessibility tree for the focused window in `get_app_state`
- the tree exposes stable numeric element indices within that snapshot
- `set_value` now resolves those indices back to live AX elements and writes through `kAXValueAttribute`

Live validation against TextEdit confirmed:

- `get_app_state("TextEdit")` returned a focused editable element:
  - `2 AXTextArea, Focused, settable`
- `set_value(app: "TextEdit", element_index: "2", value: "hello from set_value")` succeeded
- the follow-up `get_app_state` showed:
  - `2 AXTextArea, Value: hello from set_value, Focused, settable`

Interpretation:

- the first element-targeted AX path is viable
- direct value mutation works for editable text controls
- current index stability should be treated as snapshot-local, not session-global

### perform_secondary_action validation

First successful AX action result:

- the clone helper now resolves indexed AX elements and performs named accessibility actions
- action-name mapping currently normalizes common human-readable names such as `Press` and `Raise` to AX constants when applicable

Live validation against Calculator confirmed:

- `perform_secondary_action(app: "com.apple.calculator", element_index: "9", action: "Press")` succeeded
- the display changed from `1423` to `142`, proving the indexed AX action path works on a real button

Current limitation:

- the initial `Raise` implementation did not stick because the generic focus-restore logic brought the previous app back to the front
- this was fixed by treating `Raise` as a non-restoring action and falling back to app activation when AX declined the action

Follow-up validation confirmed:

- `perform_secondary_action(app: "com.apple.calculator", element_index: "0", action: "Raise")` now succeeds
- after the call, Calculator is the frontmost app in `list_apps`

### get_app_state fidelity improvements

Recent snapshot-layer improvements:

- `get_app_state` now returns structured AX metadata per element, not just bare indices
- element records now include at least:
  - `role`
  - `title`
  - `value`
  - `focused`
  - `settable`
  - `actions`
  - `bounds`
- the server now emits image content for `get_app_state` when a screenshot artifact is available

Live validation against TextEdit confirmed:

- `get_app_state("TextEdit")` returned both:
  - `contentTypes: ["text", "image"]`
  - a non-empty `artifacts.screenshotBase64`
- the top-level window element included real metadata such as:
  - `role: "AXWindow"`
  - `title: "Sans titre"`
  - `actions: ["AXRaise"]`
  - concrete `bounds`

Implementation note:

- helper-owned screenshot capture now works in the normal path through bounds-based capture from the Swift helper
- the backend-side Node fallback remains in place as a safety net if helper capture fails
- live validation confirmed screenshot artifacts on both:
  - `get_app_state("com.apple.calculator")`
  - post-action state from `press_key`

### semantic element ID improvements

Recent compatibility improvement:

- `get_app_state` now emits a clone-side semantic `id` per element in addition to traversal-order `index`
- those IDs are rendered into `treeText`, for example:
  - `0 ... ID: main`
  - `7 AXScrollArea ... ID: StandardInputView`
  - `9 AXButton ... ID: AllClear`
- action tools now resolve `element_index` against either numeric index or semantic ID

Live validation against Calculator confirmed:

- `perform_secondary_action(app: "com.apple.calculator", element_index: "AllClear", action: "Press")` succeeded

Implication:

- the clone is no longer locked to snapshot-local numeric indices for element targeting
- this meaningfully narrows the compatibility gap with the bundled Codex Computer Use plugin

### treeText formatting improvements

Recent compatibility improvement:

- the human-facing `treeText` output is now formatted closer to the bundled plugin
- lines now use:
  - readable role labels like `standard window`, `button`, `scroll area`, `menu button`
  - inline `ID: ...`
  - `Secondary Actions: ...` for non-primary actions like `Raise` and `ShowMenu`

Live validation against Calculator now renders lines such as:

- `0 standard window Calculette, ID: main, Secondary Actions: Raise`
- `9 button, Description: Supprimer, ID: Delete`
- `29 menu button, Description: calculator.fill, ID: CalculatorFill, Secondary Actions: ShowMenu`

Implication:

- the clone’s text output is no longer obviously raw AX debug output
- remaining text-fidelity gaps are now narrower and mostly about exact phrasing/localization parity

### background-pointer groundwork

Recent interaction-layer improvement:

- pointer actions now use a helper-owned overlay cursor in the Swift helper
- the overlay animates between points for:
  - `click`
  - `drag`
  - `scroll`
- the overlay is now slightly translucent and adds a small pulse on click/drag-end/scroll
- the overlay now persists across steps and fades only after a short idle period instead of disappearing immediately after each action
- `click` now uses the same focus-save/restore pattern as the other background-style actions instead of leaving the target app frontmost

Validation:

- `click`, `scroll`, and screenshot refresh still succeed with the overlay path enabled
- frontmost-app check after a clone `click` into Calculator showed:
  - before: `Codex`
  - after: `Codex`

Implication:

- pointer actions are now less disruptive by default
- the clone now has a session-like visible pointer layer rather than a per-action debug marker

Current limitation:

- the overlay visual was validated indirectly through successful action execution and focus behavior, not yet by a dedicated visual assertion harness
- the cursor look/motion is closer to Codex Computer Use, but still not a pixel-match clone

### background-first AX actions

Recent behavior change:

- `set_value` now tries AX mutation without activating the target app first
- `perform_secondary_action` now tries AX action execution without activation first, then falls back only if needed
- `Raise` remains intentionally activating because that action is about foregrounding the target

Live validation:

- with `Codex` frontmost, `perform_secondary_action(app: "com.apple.calculator", element_index: "AllClear", action: "Press")` succeeded
- frontmost app before and after remained `Codex`
- `set_value` on a live `TextEdit` text area also succeeded without requiring an activation-first path

Implication:

- AX-backed actions can now genuinely behave like background actions in at least some cases
- keyboard and pointer event tools should still be treated as best-effort restore, not true always-background actions

### list_apps filtering improvements

Recent compatibility improvement:

- `list_apps` no longer dumps raw helper/process inventory
- it now:
  - prefers user-facing running apps
  - dedupes multiple instances of the same bundle
  - keeps frontmost and visible apps prioritized
  - includes a `visible` flag in structured output

Live validation in the current shell-hosted path showed:

- earlier output: 70+ entries dominated by helpers and agents
- current output: 17 user-facing apps

Remaining gap:

- still no recent-app history
- still no `last-used`
- still no `uses` count

## Open Reverse-Engineering Questions

1. What raw MCP `CallToolResult` structure is behind the rendered output?
2. Are screenshots represented as image content items, attachments, or some Codex-specific wrapper?
3. What exact approval callback flow is used when a new app requires permission?
4. What exact per-turn reset semantics are enforced by the host?
5. Are element indices stable only within a single tool result, or across a longer app session?

## Clone Guidance

For an initial clone, it is probably not necessary to reproduce the hidden Codex hosting/runtime behavior exactly.

A practical clone can instead aim for:

- the same tool names
- the same input schemas
- similar success text + screenshot outputs
- similar text error outputs
- app/session bookkeeping internal to the clone

That should be enough for executor/planner compatibility before deeper wire-level parity work.
