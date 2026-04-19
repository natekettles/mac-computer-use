export const COMPUTER_USE_TOOL_NAMES = [
  "list_apps",
  "get_app_state",
  "click",
  "drag",
  "type_text",
  "press_key",
  "set_value",
  "scroll",
  "perform_secondary_action",
] as const;

export type ComputerUseToolName = (typeof COMPUTER_USE_TOOL_NAMES)[number];

export interface ComputerUseAppRef {
  name?: string;
  bundleId?: string;
  pid?: number;
}

export interface ComputerUseElement {
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

export interface ComputerUseSnapshot {
  windowTitle?: string;
  treeText: string;
  elements: ComputerUseElement[];
}

export interface ComputerUseArtifacts {
  screenshotMimeType?: string;
  screenshotBase64?: string;
}

export interface ComputerUseError {
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

export interface ComputerUseResultMeta {
  observedShape: "text" | "text_error" | "state+image";
  rawText?: string;
}

export interface ComputerUseSuccessResult {
  ok: true;
  toolName: ComputerUseToolName;
  app?: ComputerUseAppRef;
  snapshot?: ComputerUseSnapshot;
  artifacts?: ComputerUseArtifacts;
  data?: Record<string, unknown>;
  warnings: string[];
  meta: ComputerUseResultMeta;
}

export interface ComputerUseErrorResult {
  ok: false;
  toolName: ComputerUseToolName;
  app?: Partial<ComputerUseAppRef>;
  error: ComputerUseError;
  warnings: string[];
  meta: ComputerUseResultMeta;
}

export type ComputerUseToolResult = ComputerUseSuccessResult | ComputerUseErrorResult;

export function createErrorResult(
  toolName: ComputerUseToolName,
  code: ComputerUseError["code"],
  message: string,
  retryable = false,
): ComputerUseErrorResult {
  return {
    ok: false,
    toolName,
    error: {
      code,
      message,
      retryable,
    },
    warnings: [],
    meta: { observedShape: "text_error", rawText: message },
  };
}

export function normalizeObservedError(toolName: ComputerUseToolName, message: string): ComputerUseErrorResult {
  if (message.startsWith("appNotFound(")) {
    return createErrorResult(toolName, "app_not_found", message);
  }

  if (
    message.includes("invalid element ID") ||
    message.includes("invalidElementID") ||
    message.includes("no longer valid")
  ) {
    return createErrorResult(toolName, "invalid_element", message);
  }

  if (message.startsWith("Accessibility error:")) {
    return createErrorResult(toolName, "accessibility_error", message);
  }

  if (
    message.includes("not authorized to send keystrokes") ||
    message.includes("not allowed assistive access") ||
    message.includes("accès d’aide")
  ) {
    return createErrorResult(toolName, "permission_denied", message);
  }

  return createErrorResult(toolName, "internal_error", message);
}

export function createStubSuccessResult(
  toolName: ComputerUseToolName,
  overrides: Partial<ComputerUseSuccessResult> = {},
): ComputerUseSuccessResult {
  return {
    ok: true,
    toolName,
    warnings: [],
    meta: {
      observedShape: toolName === "list_apps" ? "text" : "state+image",
    },
    ...overrides,
  };
}
