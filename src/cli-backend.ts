import { execFile, spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import {
  createErrorResult,
  type ComputerUseAppRef,
  type ComputerUseErrorResult,
  type ComputerUseSuccessResult,
} from "./contract.js";
import type {
  ClickParams,
  ComputerUseBackend,
  DragParams,
  GetAppStateParams,
  ListAppsParams,
  PerformSecondaryActionParams,
  PressKeyParams,
  ScrollParams,
  SetValueParams,
  TypeTextParams,
} from "./backend.js";

const execFileAsync = promisify(execFile);

interface RunningAppRecord {
  name: string;
  bundleId: string | null;
  frontmost: boolean;
  visible: boolean;
}

export class CliComputerUseBackend implements ComputerUseBackend {
  async listApps(_params: ListAppsParams): Promise<ComputerUseSuccessResult | ComputerUseErrorResult> {
    try {
      const apps = await listRunningApps();
      const normalizedApps = apps
        .filter((app) => app.bundleId)
        .map((app) => ({
          name: app.name,
          bundleId: app.bundleId ?? undefined,
          running: true,
          frontmost: app.frontmost,
          visible: app.visible,
        }));

      return {
        ok: true,
        toolName: "list_apps",
        warnings: [
          "CLI backend currently enumerates running apps only; it does not include recent app history, last-used timestamps, or usage counts.",
        ],
        meta: {
          observedShape: "text",
          rawText: normalizedApps
            .map((app) => `${app.name} — ${app.bundleId} [running]`)
            .join("\n"),
        },
        data: {
          apps: normalizedApps,
        },
      };
    } catch (error) {
      return createErrorResult("list_apps", "internal_error", String(error));
    }
  }

  async getAppState(params: GetAppStateParams): Promise<ComputerUseSuccessResult | ComputerUseErrorResult> {
    const app = await resolveRunningApp(params.app);
    if (!app) {
      return createErrorResult("get_app_state", "app_not_found", `appNotFound("${params.app}")`);
    }

    const screenshot = await captureScreenshotBase64();
    const permissionOrWindows = await readAppWindows(app.name);
    if ("error" in permissionOrWindows) {
      return {
        ...permissionOrWindows.error,
        app: {
          name: app.name,
          bundleId: app.bundleId ?? undefined,
        },
      };
    }

    const treeText = [
      `App=${app.bundleId ?? app.name}`,
      `Window: "${permissionOrWindows.windows[0] ?? "<unknown>"}", App: ${app.name}.`,
    ].join("\n");

    return {
      ok: true,
      toolName: "get_app_state",
      app: {
        name: app.name,
        bundleId: app.bundleId ?? undefined,
      },
      snapshot: {
        windowTitle: permissionOrWindows.windows[0],
        treeText,
        elements: [],
      },
      artifacts: screenshot
        ? {
            screenshotMimeType: "image/png",
            screenshotBase64: screenshot,
          }
        : undefined,
      warnings: [
        "CLI backend currently returns a minimal window snapshot and does not yet reproduce the full accessibility tree.",
      ],
      meta: {
        observedShape: "state+image",
        rawText: treeText,
      },
    };
  }

  async click(_params: ClickParams) {
    const app = await resolveRunningApp(_params.app);
    if (!app) {
      return createErrorResult("click", "app_not_found", `appNotFound("${_params.app}")`);
    }

    if (_params.element_index) {
      return createErrorResult(
        "click",
        "unsupported_action",
        "CLI backend does not implement element-index click yet. Use coordinates for now.",
      );
    }

    if (typeof _params.x !== "number" || typeof _params.y !== "number") {
      return createErrorResult(
        "click",
        "unsupported_action",
        "CLI backend currently requires x/y coordinates for click.",
      );
    }

    if (_params.mouse_button && _params.mouse_button !== "left") {
      return createErrorResult(
        "click",
        "unsupported_action",
        `CLI backend currently supports left click only, not ${_params.mouse_button}.`,
      );
    }

    if (_params.click_count && _params.click_count !== 1) {
      return createErrorResult(
        "click",
        "unsupported_action",
        `CLI backend currently supports click_count=1 only, not ${_params.click_count}.`,
      );
    }

    try {
      await runAppleScript(
        [
          app.bundleId
            ? `tell application id ${appleScriptString(app.bundleId)} to activate`
            : `tell application ${appleScriptString(app.name)} to activate`,
          'tell application "System Events"',
          `  click at {${Math.round(_params.x)}, ${Math.round(_params.y)}}`,
          "end tell",
        ].join("\n"),
      );
    } catch (error) {
      return normalizeClickError(String(error));
    }

    return postPointerActionResult(
      "click",
      app,
      `Clicked at (${Math.round(_params.x)}, ${Math.round(_params.y)}) in ${app.name}.`,
    );
  }

  async drag(_params: DragParams) {
    return createErrorResult("drag", "unsupported_action", "CLI backend does not implement drag yet.");
  }

  async typeText(_params: TypeTextParams) {
    const app = await resolveRunningApp(_params.app);
    if (!app) {
      return createErrorResult("type_text", "app_not_found", `appNotFound("${_params.app}")`);
    }

    try {
      await runAppleScript(
        [
          app.bundleId
            ? `tell application id ${appleScriptString(app.bundleId)} to activate`
            : `tell application ${appleScriptString(app.name)} to activate`,
          'tell application "System Events"',
          `  keystroke ${appleScriptString(_params.text)}`,
          "end tell",
        ].join("\n"),
      );
    } catch (error) {
      return normalizeCliActionError("type_text", String(error));
    }

    return postActionResult("type_text", app, `Typed text into ${app.name}.`);
  }

  async pressKey(_params: PressKeyParams) {
    const app = await resolveRunningApp(_params.app);
    if (!app) {
      return createErrorResult("press_key", "app_not_found", `appNotFound("${_params.app}")`);
    }

    const parsed = parseKeyChord(_params.key);
    if (!parsed) {
      return createErrorResult("press_key", "unsupported_action", `Unsupported key syntax: ${_params.key}`);
    }

    try {
      await runAppleScript(
        [
          app.bundleId
            ? `tell application id ${appleScriptString(app.bundleId)} to activate`
            : `tell application ${appleScriptString(app.name)} to activate`,
          'tell application "System Events"',
          `  ${parsed}`,
          "end tell",
        ].join("\n"),
      );
    } catch (error) {
      return normalizeCliActionError("press_key", String(error));
    }

    return postActionResult("press_key", app, `Pressed key ${_params.key} in ${app.name}.`);
  }

  async setValue(_params: SetValueParams) {
    return createErrorResult("set_value", "unsupported_action", "CLI backend does not implement set_value yet.");
  }

  async scroll(_params: ScrollParams) {
    return createErrorResult("scroll", "unsupported_action", "CLI backend does not implement scroll yet.");
  }

  async performSecondaryAction(_params: PerformSecondaryActionParams) {
    return createErrorResult(
      "perform_secondary_action",
      "unsupported_action",
      "CLI backend does not implement perform_secondary_action yet.",
    );
  }
}

async function listRunningApps(): Promise<RunningAppRecord[]> {
  const script = `
    const se = Application('System Events');
    const apps = se.applicationProcesses().map((p) => ({
      name: p.name(),
      bundleId: p.bundleIdentifier(),
      frontmost: p.frontmost(),
      visible: p.visible()
    }));
    console.log(JSON.stringify(apps));
  `;
  return runJxaJson<RunningAppRecord[]>(script);
}

async function resolveRunningApp(appRef: string): Promise<RunningAppRecord | null> {
  const apps = await listRunningApps();
  const exact = apps.find((app) => app.bundleId === appRef || app.name === appRef);
  if (exact) {
    return exact;
  }

  const folded = appRef.toLowerCase();
  return apps.find((app) => app.name.toLowerCase() === folded || app.bundleId?.toLowerCase() === folded) ?? null;
}

async function readAppWindows(appName: string): Promise<{ windows: string[] } | { error: ComputerUseErrorResult }> {
  const script = `
    try {
      const se = Application('System Events');
      const proc = se.processes.byName(${JSON.stringify(appName)});
      const windows = proc.windows().map((w) => w.name());
      console.log(JSON.stringify({ windows }));
    } catch (error) {
      console.log(JSON.stringify({ error: String(error) }));
    }
  `;
  const result = await runJxaJson<{ windows?: string[]; error?: string }>(script);
  if (result.error) {
    if (result.error.includes("accès d’aide") || result.error.includes("assistive access")) {
      return {
        error: createErrorResult("get_app_state", "permission_denied", result.error),
      };
    }
    return {
      error: createErrorResult("get_app_state", "internal_error", result.error),
    };
  }
  return { windows: result.windows ?? [] };
}

async function captureScreenshotBase64(): Promise<string | undefined> {
  const tempFile = path.join(os.tmpdir(), `computer-use-clone-${process.pid}-${Date.now()}.png`);
  try {
    await execFileAsync("screencapture", ["-x", "-t", "png", tempFile]);
    const bytes = await fs.readFile(tempFile);
    return bytes.toString("base64");
  } catch {
    return undefined;
  } finally {
    await fs.rm(tempFile, { force: true }).catch(() => undefined);
  }
}

async function runJxaJson<T>(script: string): Promise<T> {
  const { stdout, stderr } = await execFileAsync("osascript", ["-l", "JavaScript", "-e", script.trim()], {
    maxBuffer: 1024 * 1024,
  });
  const payload = `${stdout}${stderr}`.trim();
  return JSON.parse(payload) as T;
}

async function runAppleScript(script: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn("osascript", ["-e", script], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    let out = "";
    let err = "";

    child.stdout.on("data", (chunk: Buffer | string) => {
      out += chunk.toString();
    });
    child.stderr.on("data", (chunk: Buffer | string) => {
      err += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`${out}${err}`.trim() || `osascript exited with code ${code ?? "unknown"}`));
    });
  });
}

function appleScriptString(value: string): string {
  return JSON.stringify(value);
}

function normalizeCliActionError(
  toolName: "press_key" | "type_text",
  message: string,
): ComputerUseErrorResult {
  if (
    message.includes("accès d’aide") ||
    message.includes("assistive access") ||
    (message.includes("System Events") && message.includes("execution error"))
  ) {
    return createErrorResult(toolName, "permission_denied", message);
  }
  return createErrorResult(toolName, "internal_error", message);
}

function normalizeClickError(message: string): ComputerUseErrorResult {
  if (
    message.includes("accès d’aide") ||
    message.includes("assistive access") ||
    (message.includes("System Events") && message.includes("execution error"))
  ) {
    return createErrorResult("click", "permission_denied", message);
  }
  return createErrorResult("click", "internal_error", message);
}

async function postActionResult(
  toolName: "press_key" | "type_text",
  app: RunningAppRecord,
  fallbackMessage: string,
): Promise<ComputerUseSuccessResult | ComputerUseErrorResult> {
  const backend = new CliComputerUseBackend();
  const state = await backend.getAppState({ app: app.bundleId ?? app.name });
  if (state.ok) {
    return {
      ...state,
      toolName,
      warnings: state.warnings,
    };
  }

  return {
    ok: true,
    toolName,
    app: {
      name: app.name,
      bundleId: app.bundleId ?? undefined,
    },
    warnings: [
      state.error.code === "permission_denied"
        ? "Action completed, but the CLI backend could not refresh app state because Accessibility permission is not granted."
        : `Action completed, but post-action state refresh failed: ${state.error.message}`,
    ],
    meta: {
      observedShape: "text",
      rawText: fallbackMessage,
    },
  };
}

async function postPointerActionResult(
  toolName: "click",
  app: RunningAppRecord,
  fallbackMessage: string,
): Promise<ComputerUseSuccessResult | ComputerUseErrorResult> {
  const backend = new CliComputerUseBackend();
  const state = await backend.getAppState({ app: app.bundleId ?? app.name });
  if (state.ok) {
    return {
      ...state,
      toolName,
      warnings: state.warnings,
    };
  }

  return {
    ok: true,
    toolName,
    app: {
      name: app.name,
      bundleId: app.bundleId ?? undefined,
    },
    warnings: [
      state.error.code === "permission_denied"
        ? "Click completed, but the CLI backend could not refresh app state because Accessibility permission is not granted."
        : `Click completed, but post-action state refresh failed: ${state.error.message}`,
    ],
    meta: {
      observedShape: "text",
      rawText: fallbackMessage,
    },
  };
}

function parseKeyChord(input: string): string | null {
  const tokens = input
    .split("+")
    .map((token) => token.trim())
    .filter((token) => token.length > 0);
  if (tokens.length === 0) {
    return null;
  }

  const keyToken = tokens[tokens.length - 1]!;
  const modifiers = tokens
    .slice(0, -1)
    .map(mapModifier)
    .filter((modifier): modifier is string => modifier !== null);

  const usingClause = modifiers.length > 0 ? ` using {${modifiers.join(", ")}}` : "";
  const special = mapSpecialKey(keyToken);
  if (special) {
    return `key code ${special}${usingClause}`;
  }

  if (keyToken.length === 1) {
    return `keystroke ${appleScriptString(keyToken)}${usingClause}`;
  }

  return null;
}

function mapModifier(input: string): string | null {
  switch (input.toLowerCase()) {
    case "cmd":
    case "command":
    case "super":
    case "meta":
      return "command down";
    case "ctrl":
    case "control":
      return "control down";
    case "alt":
    case "option":
      return "option down";
    case "shift":
      return "shift down";
    default:
      return null;
  }
}

function mapSpecialKey(input: string): number | null {
  switch (input.toLowerCase()) {
    case "return":
    case "enter":
      return 36;
    case "tab":
      return 48;
    case "space":
      return 49;
    case "escape":
    case "esc":
      return 53;
    case "delete":
    case "backspace":
      return 51;
    case "up":
      return 126;
    case "down":
      return 125;
    case "left":
      return 123;
    case "right":
      return 124;
    default:
      return null;
  }
}
