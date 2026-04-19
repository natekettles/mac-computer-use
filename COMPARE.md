# Computer Use Clone vs Codex Computer Use

## Scope

This compares the current `computer-use/` clone against the bundled Codex `@Computer Use` plugin based on:

- local static checks and tests
- live clone probes through the current native-helper backend
- live bundled-plugin probes through `mcp__computer_use__*`
- earlier live validations already recorded in [`NOTES.md`](./NOTES.md)

Date: `2026-04-18`

## Validation Summary

Local project validation is clean:

- `npm run check`: pass
- `npm test`: pass

Bundled Codex Computer Use was probed live for:

- `list_apps`
- `get_app_state("com.apple.calculator")`
- `perform_secondary_action("Press")` on Calculator in earlier validation

Clone Computer Use was probed live for:

- `list_apps`
- `get_app_state("com.apple.calculator")`
- `perform_secondary_action("Raise")`
- `perform_secondary_action("Press")`

Earlier live clone validations already completed and still relevant:

- `click` on Calculator
- `drag` on Calculator window
- `press_key` on Calculator
- `type_text` on Calculator
- `scroll` in Chrome
- `set_value` in TextEdit
- `perform_secondary_action("Press")` and `("Raise")` in earlier unsandboxed validation runs

## Tool Surface Parity

The clone exposes the same 9 tool names as the bundled plugin:

- `list_apps`
- `get_app_state`
- `click`
- `drag`
- `type_text`
- `press_key`
- `set_value`
- `scroll`
- `perform_secondary_action`

This part is effectively matched.

## What Matches Well

### 1. Core action coverage exists

The clone now has real implementations for all 9 tools, not stubs.

Confirmed earlier in live runs:

- `click` changed Calculator display from `123` to `12`
- `press_key` changed Calculator display through a real key sequence
- `type_text` appended digits in Calculator
- `scroll` moved a real Chrome page
- `drag` moved the Calculator window
- `set_value` changed a real `AXTextArea` in TextEdit
- `perform_secondary_action("Raise")` now correctly brings the target app forward

### 2. `get_app_state` shape is directionally close

The clone now returns:

- text summary
- image content in MCP output
- structured elements
- AX metadata including role, title, value, focused, settable, actions, and bounds

That is the right architectural direction and broadly matches the bundled plugin’s model of "snapshot first, actions on top."

### 3. Post-action state refresh is close

For successful native action paths, the clone returns refreshed state and image content rather than a bare acknowledgment. That is aligned with the bundled plugin behavior.

## Current Gaps vs Bundled Codex Computer Use

### 1. `list_apps` metadata parity is now strong, but ordering parity still differs

Bundled plugin output is richer:

- includes running and non-running recent apps
- includes `last-used`
- includes `uses`
- returned a populated list in this session

Clone output after today’s helper fix:

- returned `ok: true`
- now returns a filtered user-facing inventory with running apps first and recent non-running apps appended
- dedupes multiple instances of the same bundle
- now includes `visible`, `lastUsed`, and `uses`
- no longer emits the old running-only warning

The remaining gap is now mostly quality:

- ordering still differs from bundled output
- some app-name normalization still differs
- the exact inclusion/exclusion set for recents still differs across apps

### 2. `get_app_state` semantics are closer, but still less polished

Bundled plugin on Calculator currently returns polished semantic output such as:

- stable semantic IDs like `main`, `AllClear`, `Add`, `Equals`
- localized human-readable role labels
- readable "Secondary Actions" labels
- a cleaner tree presentation

Clone output is more raw:

- element identity now includes clone-side semantic IDs like `main`, `Delete`, and `StandardInputView`
- `click` and `scroll` now use bundled-style numeric `element_index` targeting
- action names are still AX-oriented in structured data like `AXRaise`
- text rendering is now much closer on the human-facing side, for example:
  - `0 fenêtre standard Calculette, ID: main, Secondary Actions: Raise`
  - `6 bouton, Description: Supprimer, ID: Delete`
  - `25 bouton de menu, Description: calculator.fill, ID: CalculatorFill, Secondary Actions: ShowMenu`
- but the clone still does not match bundled phrasing and localization exactly

The clone is useful, but not yet interchangeable at the semantic level.

### 3. `perform_secondary_action("Press")` works, but identity parity still does not fully

Bundled plugin behavior:

- `perform_secondary_action(app: "com.apple.calculator", element_index: "6", action: "Press")` worked
- it changed Calculator state from `AllClear`/`Delete` as expected in earlier validation

Clone behavior after today’s retest:

- `perform_secondary_action(app: "com.apple.calculator", element_index: "9", action: "Press")` succeeded
- `perform_secondary_action(app: "com.apple.calculator", element_index: "AllClear", action: "Press")` also succeeded
- the helper now falls back to a coordinate click when AX refuses `AXPress`

Important nuance:

- bundled and clone element numbering do not match
- bundled uses semantic labels like `AllClear`, `Add`, `Equals`
- clone still uses snapshot-local traversal indices like `9`

So the remaining gap is not whether `Press` works. It is whether callers can target the same element identity model across implementations.

### 4. Screenshot ownership is mostly fixed

Bundled plugin appears to own screenshot capture natively.

Clone behavior:

- image output is present on both `get_app_state` and post-action results
- helper-owned capture now works in the normal path using bounds-based capture from the Swift helper
- the Node backend fallback still exists, but mainly as a safety net now

Remaining gap:

- capture is still bounds-based rather than a richer app/window-native capture stack like the bundled plugin likely uses
- the fallback layering is still more pragmatic than elegant

### 5. Runtime behavior is still split by host context

The native helper has already shown two different realities:

- in earlier unsandboxed validation runs, actions worked well
- shell-hosted probing historically exposed rough edges that bundled Computer Use does not show

That means the clone is not yet operationally stable across launch contexts. The bundled plugin clearly is.

## Practical Read

If the question is "do we already have a believable clone skeleton?", the answer is yes.

If the question is "can we treat it as behaviorally equivalent to the bundled Codex Computer Use plugin?", the answer is still no.

Today’s comparison says:

- tool surface parity: strong
- action coverage: strong
- snapshot architecture: directionally correct
- semantic fidelity: partial
- runtime robustness: better, but still behind the bundled plugin
- background interaction UX: now closer, with focus restore on `click` and a helper-owned pointer overlay that persists across steps
- background semantics: materially improved for AX-backed actions, which can now succeed while keeping `Codex` frontmost

## Highest-Value Compatibility Polish Next

Before adding new features, the highest-value polish items are:

1. Filter and enrich `list_apps` so it looks more like user-facing app inventory and less like raw process inventory.
2. Tighten `list_apps` ordering and naming normalization so it lands closer to bundled output.
3. Decide how aggressively to chase background semantics for pointer actions, which likely cannot be truly background-safe across all apps.
4. Tune the overlay pointer further only if the current motion/look still feels materially off.
5. Add richer compatibility mapping for action names and element identity across changing trees.
