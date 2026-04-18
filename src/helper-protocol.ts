import type { ComputerUseToolResult } from "./contract.js";

export type HelperMethod =
  | "list_apps"
  | "get_app_state"
  | "click"
  | "drag"
  | "press_key"
  | "perform_secondary_action"
  | "set_value"
  | "type_text"
  | "scroll";

export interface HelperRequest {
  id: string;
  method: HelperMethod;
  params: Record<string, unknown>;
}

export interface HelperResponse {
  id: string;
  ok: boolean;
  result?: ComputerUseToolResult;
  error?: string;
}
