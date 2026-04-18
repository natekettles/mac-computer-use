import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";

import { createErrorResult, type ComputerUseToolResult } from "./contract.js";
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
import type { HelperRequest, HelperResponse, HelperMethod } from "./helper-protocol.js";

const execFileAsync = promisify(execFile);

export class NativeHelperBackend implements ComputerUseBackend {
  private child: ChildProcessWithoutNullStreams | null = null;
  private readonly pending = new Map<
    string,
    {
      resolve: (result: ComputerUseToolResult) => void;
      reject: (error: Error) => void;
    }
  >();
  private nextId = 0;

  async listApps(_params: ListAppsParams): Promise<ComputerUseToolResult> {
    return this.send("list_apps", {});
  }

  async getAppState(params: GetAppStateParams): Promise<ComputerUseToolResult> {
    return this.send("get_app_state", params as unknown as Record<string, unknown>);
  }

  async click(_params: ClickParams): Promise<ComputerUseToolResult> {
    return this.send("click", _params as unknown as Record<string, unknown>);
  }

  async drag(_params: DragParams): Promise<ComputerUseToolResult> {
    return this.send("drag", _params as unknown as Record<string, unknown>);
  }

  async typeText(_params: TypeTextParams): Promise<ComputerUseToolResult> {
    return this.send("type_text", _params as unknown as Record<string, unknown>);
  }

  async pressKey(_params: PressKeyParams): Promise<ComputerUseToolResult> {
    return this.send("press_key", _params as unknown as Record<string, unknown>);
  }

  async setValue(_params: SetValueParams): Promise<ComputerUseToolResult> {
    return this.send("set_value", _params as unknown as Record<string, unknown>);
  }

  async scroll(_params: ScrollParams): Promise<ComputerUseToolResult> {
    return this.send("scroll", _params as unknown as Record<string, unknown>);
  }

  async performSecondaryAction(_params: PerformSecondaryActionParams): Promise<ComputerUseToolResult> {
    return this.send("perform_secondary_action", _params as unknown as Record<string, unknown>);
  }

  private async send(method: HelperMethod, params: Record<string, unknown>): Promise<ComputerUseToolResult> {
    const child = this.ensureChild();
    const id = `req_${++this.nextId}`;
    const request: HelperRequest = { id, method, params };

    const result = await new Promise<ComputerUseToolResult>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      child.stdin.write(`${JSON.stringify(request)}\n`);
    });

    return this.withScreenshot(result);
  }

  private async withScreenshot(result: ComputerUseToolResult): Promise<ComputerUseToolResult> {
    if (!result.ok || result.meta.observedShape !== "state+image" || result.artifacts?.screenshotBase64) {
      return result;
    }

    const bounds = result.snapshot?.elements?.[0]?.bounds;
    if (!bounds) {
      return result;
    }

    const tempPath = path.join(os.tmpdir(), `computer-use-${Date.now()}-${Math.random().toString(16).slice(2)}.png`);
    try {
      await execFileAsync("/usr/sbin/screencapture", [
        "-x",
        `-R${Math.round(bounds.x)},${Math.round(bounds.y)},${Math.round(bounds.width)},${Math.round(bounds.height)}`,
        tempPath,
      ]);
      const screenshotBase64 = await fs.readFile(tempPath, "base64");
      return {
        ...result,
        artifacts: {
          screenshotMimeType: "image/png",
          screenshotBase64,
        },
        warnings: result.warnings.filter((warning) => warning !== "Native helper screenshot capture is not implemented yet."),
      };
    } catch {
      return result;
    } finally {
      await fs.rm(tempPath, { force: true }).catch(() => {});
    }
  }

  private ensureChild(): ChildProcessWithoutNullStreams {
    if (this.child) {
      return this.child;
    }

    const helperPath = path.join(process.cwd(), "helper", "ComputerUseNativeHelper.swift");
    const cachePath = path.join(process.cwd(), ".swift-cache");
    const homePath = path.join(process.cwd(), ".swift-home");
    const child = spawn("swift", [helperPath], {
      cwd: process.cwd(),
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        HOME: homePath,
        CLANG_MODULE_CACHE_PATH: cachePath,
        SWIFT_MODULECACHE_PATH: cachePath,
      },
    });

    const stdout = readline.createInterface({ input: child.stdout });
    stdout.on("line", (line) => {
      if (!line.trim()) {
        return;
      }

      let parsed: HelperResponse;
      try {
        parsed = JSON.parse(line) as HelperResponse;
      } catch (error) {
        this.rejectAll(new Error(`Failed to parse native helper response: ${String(error)}`));
        return;
      }

      const pending = this.pending.get(parsed.id);
      if (!pending) {
        return;
      }
      this.pending.delete(parsed.id);

      if (parsed.ok && parsed.result) {
        pending.resolve(parsed.result);
        return;
      }

      pending.reject(new Error(parsed.error ?? "Native helper request failed."));
    });

    let stderr = "";
    child.stderr.on("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      this.rejectAll(error instanceof Error ? error : new Error(String(error)));
      this.child = null;
    });

    child.on("close", (code) => {
      const detail = stderr.trim().length > 0 ? ` ${stderr.trim()}` : "";
      this.rejectAll(new Error(`Native helper exited with code ${code ?? "unknown"}.${detail}`));
      this.child = null;
    });

    this.child = child;
    return child;
  }

  private rejectAll(error: Error): void {
    for (const pending of this.pending.values()) {
      pending.reject(error);
    }
    this.pending.clear();
  }
}
