import assert from "node:assert/strict";
import test from "node:test";

import type { HelperRequest, HelperResponse } from "../src/helper-protocol.js";

test("helper protocol request shape is newline-json friendly", () => {
  const request: HelperRequest = {
    id: "req_1",
    method: "get_app_state",
    params: { app: "com.apple.calculator" },
  };

  const encoded = JSON.stringify(request);
  const decoded = JSON.parse(encoded) as HelperRequest;

  assert.equal(decoded.id, "req_1");
  assert.equal(decoded.method, "get_app_state");
  assert.equal(decoded.params.app, "com.apple.calculator");
});

test("helper protocol response can carry structured result payloads", () => {
  const response: HelperResponse = {
    id: "req_1",
    ok: true,
    result: {
      ok: true,
      toolName: "list_apps",
      warnings: [],
      data: { apps: [] },
      meta: { observedShape: "text", rawText: "" },
    },
  };

  const roundTrip = JSON.parse(JSON.stringify(response)) as HelperResponse;
  assert.equal(roundTrip.ok, true);
  assert.equal(roundTrip.result?.toolName, "list_apps");
});
