import type { ComputerUseAppRef, ComputerUseElement, ComputerUseSnapshot } from "./contract.js";

const APP_LINE_PATTERN = /^(?<name>.+) — (?<bundleId>\S+) \[(?<meta>.+)\]$/u;
const APP_STATE_APP_PATTERN = /^App=(?<bundleId>\S+)(?: \(pid (?<pid>\d+)\))?$/u;
const WINDOW_PATTERN = /^Window: "(?<title>.*)", App: (?<appName>.+)\.$/u;

export interface ParsedObservedAppList {
  apps: Array<
    ComputerUseAppRef & {
      running?: boolean;
      lastUsed?: string;
      uses?: number;
    }
  >;
}

export interface ParsedObservedAppState {
  app?: ComputerUseAppRef;
  snapshot: ComputerUseSnapshot;
}

export function parseObservedAppList(text: string): ParsedObservedAppList {
  const apps = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .flatMap((line) => {
      const match = line.match(APP_LINE_PATTERN);
      if (!match?.groups) {
        return [];
      }
      const { name, bundleId, meta } = match.groups;
      if (!name || !bundleId || !meta) {
        return [];
      }

      const metaParts = meta.split(",").map((part) => part.trim());
      const running = metaParts.includes("running");
      const lastUsed = metaParts.find((part) => part.startsWith("last-used="))?.slice("last-used=".length);
      const usesText = metaParts.find((part) => part.startsWith("uses="))?.slice("uses=".length);
      const uses = usesText ? Number.parseInt(usesText, 10) : undefined;

      return [{
        name,
        bundleId,
        running,
        lastUsed,
        uses: Number.isNaN(uses) ? undefined : uses,
      }];
    });

  return { apps };
}

export function parseObservedAppState(text: string): ParsedObservedAppState {
  const lines = text.split("\n").map((line) => line.replace(/\r$/, ""));
  const bodyLines = stripAppStateEnvelope(lines).filter((line) => line.trim().length > 0);

  let app: ComputerUseAppRef | undefined;
  let windowTitle: string | undefined;
  const roots: ComputerUseElement[] = [];
  const stack: Array<{ depth: number; element: ComputerUseElement }> = [];

  for (const line of bodyLines) {
    const trimmed = line.trim();

    const appMatch = trimmed.match(APP_STATE_APP_PATTERN);
    if (appMatch?.groups) {
      app = {
        bundleId: appMatch.groups.bundleId,
        pid: appMatch.groups.pid ? Number.parseInt(appMatch.groups.pid, 10) : undefined,
      };
      continue;
    }

    const windowMatch = trimmed.match(WINDOW_PATTERN);
    if (windowMatch?.groups) {
      windowTitle = windowMatch.groups.title;
      app ??= {};
      app.name = windowMatch.groups.appName;
      continue;
    }

    const parsedElement = parseObservedElement(line);
    if (!parsedElement) {
      continue;
    }

    const { depth, element } = parsedElement;
    while (stack.length > 0 && stack[stack.length - 1]!.depth >= depth) {
      stack.pop();
    }

    const parent = stack[stack.length - 1]?.element;
    if (parent) {
      parent.children ??= [];
      parent.children.push(element);
    } else {
      roots.push(element);
    }

    stack.push({ depth, element });
  }

  return {
    app,
    snapshot: {
      windowTitle,
      treeText: bodyLines.join("\n"),
      elements: roots,
    },
  };
}

function stripAppStateEnvelope(lines: string[]): string[] {
  return lines.filter((line) => line !== "<app_state>" && line !== "</app_state>" && !line.startsWith("Computer Use state"));
}

function parseObservedElement(line: string): { depth: number; element: ComputerUseElement } | null {
  const match = line.match(/^(?<indent>\t*)(?<index>\d+)\s+(?<rest>.+)$/u);
  if (!match?.groups) {
    return null;
  }
  const { indent, index, rest } = match.groups;
  if (indent === undefined || index === undefined || rest === undefined) {
    return null;
  }

  const rawRest = rest.trim();
  const depth = indent.length;
  const element: ComputerUseElement = {
    index,
  };

  const idMatch = rawRest.match(/, ID: (?<id>[^,]+)$/u);
  if (idMatch?.groups?.id) {
    element.title = idMatch.groups.id;
  }

  const actionsMatch = rawRest.match(/, Secondary Actions: (?<actions>.+?)(?:, ID:|$)/u);
  if (actionsMatch?.groups?.actions) {
    element.actions = actionsMatch.groups.actions.split(",").map((entry) => entry.trim()).filter((entry) => entry.length > 0);
  }

  const helpMatch = rawRest.match(/, Help: (?<help>.+?)(?:, ID:|$)/u);
  if (helpMatch?.groups?.help) {
    element.help = helpMatch.groups.help;
  }

  const descriptionMatch = rawRest.match(/Description: (?<description>.+?)(?:, Help:|, ID:|$)/u);
  if (descriptionMatch?.groups?.description) {
    element.description = descriptionMatch.groups.description;
  }

  const base = rawRest
    .replace(/, Secondary Actions: .+?(?=, ID:|$)/u, "")
    .replace(/, Help: .+?(?=, ID:|$)/u, "")
    .replace(/Description: .+?(?=, Help:|, ID:|$)/u, "")
    .replace(/, ID: .+$/u, "")
    .trim();

  const roleAndMaybeValue = base.match(/^(?<role>.+?)(?:\s+\((?<flags>[^)]+)\))?(?:\s+(?<value>.+))?$/u);
  if (roleAndMaybeValue?.groups) {
    element.role = roleAndMaybeValue.groups.role;
    const flags = roleAndMaybeValue.groups.flags?.split(",").map((flag) => flag.trim()) ?? [];
    if (flags.includes("disabled")) {
      element.enabled = false;
    }
    if (flags.includes("settable")) {
      element.settable = true;
    }
    if (roleAndMaybeValue.groups.value) {
      element.value = roleAndMaybeValue.groups.value;
    }
  }

  return { depth, element };
}
