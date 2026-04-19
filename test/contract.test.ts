import assert from "node:assert/strict";
import test from "node:test";

import { COMPUTER_USE_TOOL_NAMES, createStubSuccessResult, normalizeObservedError } from "../src/contract.js";

test("contract exposes the observed tool names", () => {
  assert.deepEqual(COMPUTER_USE_TOOL_NAMES, [
    "list_apps",
    "get_app_state",
    "click",
    "drag",
    "type_text",
    "press_key",
    "set_value",
    "scroll",
    "perform_secondary_action",
  ]);
});

test("normalizeObservedError maps known app not found errors", () => {
  const result = normalizeObservedError("get_app_state", 'appNotFound("Calculette")');
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "app_not_found");
});

test("normalizeObservedError maps known accessibility errors", () => {
  const result = normalizeObservedError("set_value", "Accessibility error: AXError.illegalArgument");
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "accessibility_error");
});

test("normalizeObservedError maps compact invalid element errors", () => {
  const result = normalizeObservedError("click", "Apple event error -10005: invalidElementID");
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "invalid_element");
});

test("normalizeObservedError maps stale element errors", () => {
  const result = normalizeObservedError(
    "click",
    "Apple event error -10005: The element ID is no longer valid. Try to get the on-screen content again."
  );
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "invalid_element");
});

test("normalizeObservedError maps assistive access failures to permission denied", () => {
  const result = normalizeObservedError("get_app_state", "Error: osascript n’est pas autorisé à un accès d’aide.");
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "permission_denied");
});

test("createStubSuccessResult uses read-vs-action observed shapes", () => {
  assert.equal(createStubSuccessResult("list_apps").meta.observedShape, "text");
  assert.equal(createStubSuccessResult("click").meta.observedShape, "state+image");
});
