import assert from "node:assert/strict";
import test from "node:test";

import { parseObservedAppList, parseObservedAppState } from "../src/observed-parser.js";

test("parseObservedAppList extracts app metadata from Codex text output", () => {
  const parsed = parseObservedAppList([
    "Google Chrome — com.google.Chrome [running, last-used=2026-04-17, uses=50671]",
    "Finder — com.apple.finder [running, last-used=2026-04-12, uses=4]",
  ].join("\n"));

  assert.equal(parsed.apps.length, 2);
  assert.deepEqual(parsed.apps[0], {
    name: "Google Chrome",
    bundleId: "com.google.Chrome",
    running: true,
    lastUsed: "2026-04-17",
    uses: 50671,
  });
});

test("parseObservedAppState extracts app, window, and tree elements", () => {
  const parsed = parseObservedAppState([
    "Computer Use state (CUA App Version: 750)",
    "<app_state>",
    "App=com.apple.calculator (pid 4287)",
    'Window: "Calculette", App: Calculette.',
    '\t0 fenêtre standard Calculette, ID: main, Secondary Actions: Raise',
    '\t\t1 zone de défilement Description: Entrée, ID: StandardInputView',
    '\t\t\t2 texte 123',
    "</app_state>",
  ].join("\n"));

  assert.equal(parsed.app?.bundleId, "com.apple.calculator");
  assert.equal(parsed.app?.pid, 4287);
  assert.equal(parsed.app?.name, "Calculette");
  assert.equal(parsed.snapshot.windowTitle, "Calculette");
  assert.equal(parsed.snapshot.elements.length, 1);
  assert.equal(parsed.snapshot.elements[0]?.index, "0");
  assert.deepEqual(parsed.snapshot.elements[0]?.actions, ["Raise"]);
  assert.equal(parsed.snapshot.elements[0]?.children?.[0]?.description, "Entrée");
  assert.equal(parsed.snapshot.elements[0]?.children?.[0]?.children?.[0]?.value, "123");
});
