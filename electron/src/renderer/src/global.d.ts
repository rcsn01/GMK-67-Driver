import type { GMK67API } from "../../shared/types";

declare global {
  interface Window {
    gmk67: GMK67API;
  }
}
