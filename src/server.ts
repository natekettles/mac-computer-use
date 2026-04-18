import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import { CliComputerUseBackend } from "./cli-backend.js";
import { NativeHelperBackend } from "./native-helper-backend.js";
import type {
  ClickParams,
  ComputerUseBackend,
  DragParams,
  PerformSecondaryActionParams,
  PressKeyParams,
  ScrollParams,
  SetValueParams,
  TypeTextParams,
} from "./backend.js";
import type { ComputerUseToolResult } from "./contract.js";

function asContent(result: ComputerUseToolResult) {
  const content: Array<{ type: "text"; text: string } | { type: "image"; data: string; mimeType: string }> = [
    { type: "text", text: renderResultText(result) },
  ];

  if (result.ok && result.artifacts?.screenshotBase64 && result.artifacts.screenshotMimeType) {
    content.push({
      type: "image",
      data: result.artifacts.screenshotBase64,
      mimeType: result.artifacts.screenshotMimeType,
    });
  }

  return content;
}

function asStructuredContent(result: ComputerUseToolResult): Record<string, unknown> {
  return result as unknown as Record<string, unknown>;
}

function renderResultText(result: ComputerUseToolResult): string {
  if (!result.ok) {
    return result.error.message;
  }

  if (typeof result.meta.rawText === "string" && result.meta.rawText.length > 0) {
    return result.meta.rawText;
  }

  if (result.toolName === "list_apps") {
    const apps = Array.isArray(result.data?.apps) ? result.data.apps : [];
    return apps.length > 0 ? JSON.stringify(apps, null, 2) : "No apps found.";
  }

  return `${result.toolName} completed.`;
}

function registerTools(server: McpServer, backend: ComputerUseBackend): void {
  server.tool("list_apps", "List apps on this computer.", {}, async () => {
    const result = await backend.listApps({});
    return {
      content: asContent(result),
      structuredContent: asStructuredContent(result),
      ...(result.ok ? {} : { isError: true }),
    };
  });

  server.tool(
    "get_app_state",
    "Get the current app state and accessibility tree.",
    { app: z.string() },
    async ({ app }) => {
      const result = await backend.getAppState({ app });
      return {
        content: asContent(result),
        structuredContent: asStructuredContent(result),
        ...(result.ok ? {} : { isError: true }),
      };
    },
  );

  server.tool(
    "click",
    "Click an element by id or coordinates.",
    {
      app: z.string(),
      click_count: z.number().int().min(1).optional(),
      element_index: z.string().optional(),
      mouse_button: z.enum(["left", "right", "middle"]).optional(),
      x: z.number().optional(),
      y: z.number().optional(),
    },
    async (params: ClickParams) => toolResponse(await backend.click(params)),
  );

  server.tool(
    "drag",
    "Drag from one coordinate to another.",
    {
      app: z.string(),
      from_x: z.number(),
      from_y: z.number(),
      to_x: z.number(),
      to_y: z.number(),
    },
    async (params: DragParams) => toolResponse(await backend.drag(params)),
  );

  server.tool(
    "type_text",
    "Type literal text into an app.",
    {
      app: z.string(),
      text: z.string(),
    },
    async (params: TypeTextParams) => toolResponse(await backend.typeText(params)),
  );

  server.tool(
    "press_key",
    "Press a key or key combination in an app.",
    {
      app: z.string(),
      key: z.string(),
    },
    async (params: PressKeyParams) => toolResponse(await backend.pressKey(params)),
  );

  server.tool(
    "set_value",
    "Set the value of a settable UI element.",
    {
      app: z.string(),
      element_index: z.string(),
      value: z.string(),
    },
    async (params: SetValueParams) => toolResponse(await backend.setValue(params)),
  );

  server.tool(
    "scroll",
    "Scroll a UI element.",
    {
      app: z.string(),
      direction: z.string(),
      element_index: z.string(),
      pages: z.number().int().min(1).optional(),
    },
    async (params: ScrollParams) => toolResponse(await backend.scroll(params)),
  );

  server.tool(
    "perform_secondary_action",
    "Invoke a secondary accessibility action on an element.",
    {
      action: z.string(),
      app: z.string(),
      element_index: z.string(),
    },
    async (params: PerformSecondaryActionParams) => toolResponse(await backend.performSecondaryAction(params)),
  );
}

function toolResponse(result: ComputerUseToolResult) {
  return {
    content: asContent(result),
    structuredContent: asStructuredContent(result),
    ...(result.ok ? {} : { isError: true }),
  };
}

export async function startServer(): Promise<void> {
  const server = new McpServer({
    name: "computer-use-clone",
    version: "0.0.0",
  });

  const backend =
    process.env.COMPUTER_USE_BACKEND === "native-helper"
      ? new NativeHelperBackend()
      : new CliComputerUseBackend();

  registerTools(server, backend);

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

if (process.argv[1]?.endsWith("server.ts")) {
  startServer().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
