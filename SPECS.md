# Computer Use MCP Clone Spec

Last updated: 2026-04-17

## Scope

This document captures the externally visible MCP surface of the bundled Codex `@Computer Use` plugin on this machine.

It is intentionally focused on:

- tool names
- input schemas
- observed runtime behavior
- observed output and error shapes

It is not yet a complete wire-level reverse engineering of the raw JSON-RPC/MCP transport.

## Source Artifacts

Local plugin manifests:

- `~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/.codex-plugin/plugin.json`
- `~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/.mcp.json`

Declared MCP server entry:

```json
{
  "mcpServers": {
    "computer-use": {
      "command": "./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient",
      "args": ["mcp"],
      "cwd": "."
    }
  }
}
```

## High-Level Behavior

- The plugin is described as: "Control desktop apps on macOS from Codex through Computer Use."
- The tool surface is app-centric and macOS-specific.
- `get_app_state` is treated as the primary read/inspect primitive.
- The client binary contains guidance strings stating:
  - call `get_app_state` before other actions in a turn
  - the available tools are `list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`, `press_key`, and `set_value`
- The binary also contains approval/session strings such as:
  - `x-codex-turn-metadata`
  - `codex.session_id`
  - `codex.turn_id`
  - `agent-turn-complete`
  - approval-related messages for app access

## Tool Catalog

### `list_apps`

Description:
- List apps on the computer, including running apps and recently used apps.

Input schema:

```json
{}
```

Observed output shape:
- Returned to the model as a text content item.
- Each line is formatted approximately as:

```text
<App Name> — <bundle id> [running?, last-used=YYYY-MM-DD, uses=<int>]
```

Observed example:

```text
Google Chrome — com.google.Chrome [running, last-used=2026-04-17, uses=50671]
Slack — com.tinyspeck.slackmacgap [running, last-used=2026-04-17, uses=16956]
Finder — com.apple.finder [running, last-used=2026-04-12, uses=4]
```

Notes:
- Current wrapper output is plain text, not observed as structured JSON.
- A clone should strongly consider returning both:
  - human-readable text
  - structured content with fields like `name`, `bundleId`, `running`, `lastUsed`, `uses`

### `get_app_state`

Description:
- Start an app use session if needed, then return the app's key window state and accessibility tree.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "app": {
      "type": "string",
      "description": "App name or bundle identifier"
    }
  },
  "required": ["app"]
}
```

Observed output shape:
- Rich mixed output rendered to the model as:
  - a text block headed with `Computer Use state (CUA App Version: 750)`
  - an `<app_state> ... </app_state>` block
  - an image/screenshot

Observed example:

```text
Computer Use state (CUA App Version: 750)
<app_state>
App=com.apple.finder (pid 522)
Window: "Desktop", App: Finder.
	0 zone de défilement (disabled) bureau
	1 menu bar
		2 Finder
		3 Fichier
		4 Édition
		5 Présentation
		6 Aller
		7 Fenêtre
		8 Aide

</app_state>
```

Notes:
- The accessibility tree uses numeric element indices.
- Element labels are localized. On this machine they appeared in French.
- A clone should preserve stable numeric element identifiers within a single returned tree.

### `click`

Description:
- Click an element by index or coordinates.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "app": { "type": "string" },
    "click_count": { "type": "integer", "minimum": 1 },
    "element_index": { "type": "string" },
    "mouse_button": {
      "type": "string",
      "enum": ["left", "right", "middle"]
    },
    "x": { "type": "number" },
    "y": { "type": "number" }
  },
  "required": ["app"]
}
```

Observed success shape:
- Returns a refreshed app/window state plus screenshot.

Observed error example:

```text
Apple event error -10005: 999999 is an invalid element ID
```

Open questions:
- Need to determine precedence rules when both `element_index` and `x`/`y` are supplied.

### `drag`

Description:
- Drag from one point to another using pixel coordinates.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "app": { "type": "string" },
    "from_x": { "type": "number" },
    "from_y": { "type": "number" },
    "to_x": { "type": "number" },
    "to_y": { "type": "number" }
  },
  "required": ["app", "from_x", "from_y", "to_x", "to_y"]
}
```

Observed output:
- Success returns refreshed app/window state plus screenshot.
- A no-op drag on Calculator still produced a full refreshed state response.

### `type_text`

Description:
- Type literal text using keyboard input.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "app": { "type": "string" },
    "text": { "type": "string" }
  },
  "required": ["app", "text"]
}
```

Observed output:
- Success returns refreshed app/window state plus screenshot.

Observed example:

```text
App=com.apple.calculator (pid 4287)
Window: "Calculette", App: Calculette.
	...
	4 zone de défilement Description: Entrée, ID: StandardInputView
		5 texte ‎123
	6 bouton Description: Supprimer, Help: Supprimer la dernière opération ou le dernier chiffre saisi (appui long pour tout supprimer), ID: Delete
	...
```

### `press_key`

Description:
- Press a key or key combination.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "app": { "type": "string" },
    "key": { "type": "string" }
  },
  "required": ["app", "key"]
}
```

Observed success example:

```text
App=com.apple.finder (pid 522)
Window: "Desktop", App: Finder.
	0 zone de défilement bureau
	1 menu bar
		2 Finder
		3 Fichier
		4 Édition
		5 Présentation
		6 Aller
		7 Fenêtre
		8 Aide
```

Notes:
- On success, the tool appears to return a refreshed app/window state and screenshot rather than a simple `"ok"` payload.

### `set_value`

Description:
- Set the value of a settable accessibility element.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "app": { "type": "string" },
    "element_index": { "type": "string" },
    "value": { "type": "string" }
  },
  "required": ["app", "element_index", "value"]
}
```

Observed output:
- Error example:

```text
Accessibility error: AXError.illegalArgument
```

Notes:
- Setting the Calculator split-view divider to `-1` produced an accessibility illegal-argument error.
- A successful `set_value` case still needs capture.

### `scroll`

Description:
- Scroll an element in a direction by a number of pages.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "app": { "type": "string" },
    "direction": { "type": "string" },
    "element_index": { "type": "string" },
    "pages": { "type": "integer", "minimum": 1 }
  },
  "required": ["app", "direction", "element_index"]
}
```

Observed output:
- Success returns refreshed app/window state plus screenshot.
- On Calculator, scrolling a non-scrollable/display-like element still returned a refreshed state rather than an explicit error.

### `perform_secondary_action`

Description:
- Invoke a secondary accessibility action exposed by an element.

Input schema:

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string" },
    "app": { "type": "string" },
    "element_index": { "type": "string" }
  },
  "required": ["action", "app", "element_index"]
}
```

Observed output:
- Success returns refreshed app/window state plus screenshot.
- Invoking `Raise` on Calculator window element `0` did not produce a special ack payload.

## Observed Output Patterns

### Read tools

Observed read-style tools:

- `list_apps`
- `get_app_state`

Observed behavior:

- `list_apps` returns plain text only.
- `get_app_state` returns text plus screenshot.

### Action tools

Observed action-style tools:

- `click`
- `drag`
- `type_text`
- `press_key`
- `scroll`
- `perform_secondary_action`

Observed behavior:

- failures may be returned as a single text error line
- successes may return a refreshed app/window state and screenshot rather than a minimal ack

This suggests a clone should support returning post-action state snapshots, not just booleans.

## Approval and Session Semantics

Observed evidence suggests the real implementation has:

- per-turn lifecycle semantics
- app approval flow
- session and turn metadata passed out-of-band

Relevant binary strings include:

- `computer_use_mcp_app_approval_requested`
- `computer_use_mcp_app_approval_resolved`
- `computer_use_mcp_approval_result`
- `x-codex-turn-metadata`
- `codex.session_id`
- `codex.turn_id`
- `agent-turn-complete`

For a clone, the minimum viable behavior should likely be:

- stateless MCP transport from the client's perspective
- internal app-session cache keyed by app
- optional approval hook before first interaction with a given app
- post-action refresh of app state for some or all mutating tools

## Live Probe Transcript

Probes run in this session:

1. `list_apps()`
2. `get_app_state({ "app": "Finder" })`
3. `click({ "app": "Finder", "element_index": "999999" })`
4. `press_key({ "app": "Finder", "key": "Escape" })`
5. `get_app_state({ "app": "com.apple.calculator" })`
6. `click({ "app": "com.apple.calculator", "element_index": "9" })`
7. `scroll({ "app": "com.apple.calculator", "element_index": "5", "direction": "down", "pages": 1 })`
8. `perform_secondary_action({ "app": "com.apple.calculator", "element_index": "0", "action": "Raise" })`
9. `type_text({ "app": "com.apple.calculator", "text": "123" })`
10. `drag({ "app": "com.apple.calculator", "from_x": 470, "from_y": 300, "to_x": 480, "to_y": 300 })`
11. `set_value({ "app": "com.apple.calculator", "element_index": "2", "value": "-1" })`

## Known Gaps

The following still need direct capture:

- raw MCP `CallToolResult` payloads before Codex/UI rendering
- successful `set_value` response
- exact approval error payloads
- exact screenshot/image item metadata shape

## Next Steps

1. Capture raw MCP tool responses from a live client if possible.
2. Probe each remaining tool with a harmless app/element.
3. Define a normalized clone schema with:
   - strict input JSON Schemas
   - structured result payloads
   - optional human-readable text mirrors
4. Separate the spec into:
   - `SPECS.md` for public external contract
   - `NOTES.md` for reverse-engineering observations
