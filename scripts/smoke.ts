import { NativeHelperBackend } from "../src/native-helper-backend.js";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function errorMessage(result: unknown): string {
  if (
    result &&
    typeof result === "object" &&
    "error" in result &&
    result.error &&
    typeof result.error === "object" &&
    "message" in result.error &&
    typeof result.error.message === "string"
  ) {
    return result.error.message;
  }

  return "unknown error";
}

async function main() {
  const backend = new NativeHelperBackend();
  const appRef = process.argv[2] ?? "com.apple.calculator";

  await launchApp(appRef);

  const apps = await backend.listApps({});
  assert(apps.ok, `list_apps failed: ${errorMessage(apps)}`);

  const appCount = Array.isArray(apps.data?.apps) ? apps.data.apps.length : 0;
  assert(appCount > 0, "list_apps returned no apps");

  const state = await backend.getAppState({ app: appRef });
  assert(state.ok, `get_app_state failed for ${appRef}: ${errorMessage(state)}`);
  assert(Boolean(state.artifacts?.screenshotBase64), "get_app_state returned no screenshot artifact");
  assert((state.snapshot?.elements?.length ?? 0) > 0, "get_app_state returned no accessibility elements");

  const frontmost =
    Array.isArray(apps.data?.apps) && apps.data.apps.find((app) => app.frontmost)?.name
      ? apps.data.apps.find((app) => app.frontmost)?.name
      : null;

  console.log(
    JSON.stringify(
      {
        ok: true,
        appRef,
        appCount,
        frontmost,
        windowTitle: state.snapshot?.windowTitle ?? null,
        elementCount: state.snapshot?.elements?.length ?? 0,
        hasImage: Boolean(state.artifacts?.screenshotBase64),
      },
      null,
      2,
    ),
  );
}

async function launchApp(appRef: string) {
  if (appRef.includes(".")) {
    await execFileAsync("open", ["-b", appRef]).catch(() => {});
  } else {
    await execFileAsync("open", ["-a", appRef]).catch(() => {});
  }

  await new Promise((resolve) => setTimeout(resolve, 1000));
}

main().catch((error) => {
  console.error(String(error instanceof Error ? error.message : error));
  process.exit(1);
});
