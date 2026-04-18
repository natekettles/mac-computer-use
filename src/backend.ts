import type { ComputerUseToolResult } from "./contract.js";

export interface ListAppsParams {}

export interface GetAppStateParams {
  app: string;
}

export interface ClickParams {
  app: string;
  click_count?: number;
  element_index?: string;
  mouse_button?: "left" | "right" | "middle";
  x?: number;
  y?: number;
}

export interface DragParams {
  app: string;
  from_x: number;
  from_y: number;
  to_x: number;
  to_y: number;
}

export interface TypeTextParams {
  app: string;
  text: string;
}

export interface PressKeyParams {
  app: string;
  key: string;
}

export interface SetValueParams {
  app: string;
  element_index: string;
  value: string;
}

export interface ScrollParams {
  app: string;
  direction: string;
  element_index: string;
  pages?: number;
}

export interface PerformSecondaryActionParams {
  action: string;
  app: string;
  element_index: string;
}

export interface ComputerUseBackend {
  listApps(params: ListAppsParams): Promise<ComputerUseToolResult>;
  getAppState(params: GetAppStateParams): Promise<ComputerUseToolResult>;
  click(params: ClickParams): Promise<ComputerUseToolResult>;
  drag(params: DragParams): Promise<ComputerUseToolResult>;
  typeText(params: TypeTextParams): Promise<ComputerUseToolResult>;
  pressKey(params: PressKeyParams): Promise<ComputerUseToolResult>;
  setValue(params: SetValueParams): Promise<ComputerUseToolResult>;
  scroll(params: ScrollParams): Promise<ComputerUseToolResult>;
  performSecondaryAction(params: PerformSecondaryActionParams): Promise<ComputerUseToolResult>;
}
