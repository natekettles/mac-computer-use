# Computer Use Clone Result Schema

Last updated: 2026-04-17

## Goal

This document defines the normalized result contract for a clone of the bundled Codex `@Computer Use` MCP.

The real implementation appears to render a mix of:

- text summaries
- accessibility tree snapshots
- screenshots
- plain text errors

For the clone, we want a structured JSON result that can be deterministically consumed by:

- MCP clients
- planners/executors
- snapshot tests

while still being easy to render into the same user-facing shape.

## Top-Level Result

Every tool returns a `ComputerUseToolResult`:

```json
{
  "ok": true,
  "toolName": "get_app_state",
  "app": {
    "name": "Calculette",
    "bundleId": "com.apple.calculator",
    "pid": 4287
  },
  "snapshot": {
    "windowTitle": "Calculette",
    "treeText": "App=com.apple.calculator (pid 4287)\nWindow: \"Calculette\", App: Calculette.\n\t...",
    "elements": []
  },
  "artifacts": {
    "screenshotMimeType": "image/png",
    "screenshotBase64": "<optional>"
  },
  "warnings": [],
  "meta": {
    "observedShape": "state+image"
  }
}
```

On failure:

```json
{
  "ok": false,
  "toolName": "set_value",
  "error": {
    "code": "accessibility_error",
    "message": "Accessibility error: AXError.illegalArgument",
    "retryable": false
  },
  "warnings": [],
  "meta": {
    "observedShape": "text_error"
  }
}
```

## Type Definitions

### `ComputerUseToolResult`

```ts
type ComputerUseToolResult =
  | ComputerUseSuccessResult
  | ComputerUseErrorResult;
```

### `ComputerUseSuccessResult`

```ts
interface ComputerUseSuccessResult {
  ok: true;
  toolName: ComputerUseToolName;
  app?: ComputerUseAppRef;
  snapshot?: ComputerUseSnapshot;
  artifacts?: ComputerUseArtifacts;
  data?: Record<string, unknown>;
  warnings: string[];
  meta: ComputerUseResultMeta;
}
```

### `ComputerUseErrorResult`

```ts
interface ComputerUseErrorResult {
  ok: false;
  toolName: ComputerUseToolName;
  app?: Partial<ComputerUseAppRef>;
  error: ComputerUseError;
  warnings: string[];
  meta: ComputerUseResultMeta;
}
```

## Supporting Types

### `ComputerUseAppRef`

```ts
interface ComputerUseAppRef {
  name?: string;
  bundleId?: string;
  pid?: number;
}
```

### `ComputerUseSnapshot`

```ts
interface ComputerUseSnapshot {
  windowTitle?: string;
  treeText: string;
  elements: ComputerUseElement[];
}
```

### `ComputerUseElement`

```ts
interface ComputerUseElement {
  index: string;
  id?: string;
  role?: string;
  title?: string;
  description?: string;
  value?: string | number | boolean;
  help?: string;
  enabled?: boolean;
  focused?: boolean;
  settable?: boolean;
  actions?: string[];
  bounds?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  children?: ComputerUseElement[];
}
```

`id` is a clone-side semantic identifier intended to be more stable than traversal-order `index`. Action tools may accept either value when targeting an element.

### `ComputerUseArtifacts`

```ts
interface ComputerUseArtifacts {
  screenshotMimeType?: string;
  screenshotBase64?: string;
}
```

### `ComputerUseError`

```ts
interface ComputerUseError {
  code:
    | "app_not_found"
    | "invalid_element"
    | "accessibility_error"
    | "permission_denied"
    | "unsupported_action"
    | "internal_error";
  message: string;
  retryable: boolean;
}
```

### `ComputerUseResultMeta`

```ts
interface ComputerUseResultMeta {
  observedShape: "text" | "text_error" | "state+image";
  rawText?: string;
}
```

## Normalization Rules

### Read tools

- `list_apps`
  - return `ok: true`
  - populate `data.apps`
  - set `meta.observedShape = "text"`
  - `snapshot` is optional

- `get_app_state`
  - return `ok: true`
  - populate `app`, `snapshot`, and optional screenshot artifact
  - set `meta.observedShape = "state+image"`

### Action tools

Observed live behavior suggests these tools usually return refreshed state plus screenshot:

- `click`
- `drag`
- `type_text`
- `press_key`
- `scroll`
- `perform_secondary_action`

Clone rule:

- return `ok: true`
- include refreshed `snapshot`
- include screenshot artifact when available
- optionally include tool-specific payload in `data`

### `set_value`

- success should follow the same refreshed-state rule
- accessibility failures normalize to `code = "accessibility_error"`

## Error Mapping

Suggested first-pass error normalization:

| Raw text | Normalized code |
| --- | --- |
| `appNotFound("...")` | `app_not_found` |
| `Apple event error -10005: ... invalid element ID` | `invalid_element` |
| `Accessibility error: AXError...` | `accessibility_error` |

## MCP Rendering Guidance

When exposing this over MCP, return:

1. a text item with a human-readable summary
2. a structured JSON object matching `ComputerUseToolResult`
3. optionally an image item for screenshot data

This keeps compatibility with both:

- human-facing chat rendering
- machine-facing structured consumers
