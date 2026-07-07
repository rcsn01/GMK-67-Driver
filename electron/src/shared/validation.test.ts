import { describe, expect, it } from "vitest";
import { normalizeHexColor, sanitizeArgs, splitSpecs } from "./validation";

describe("validation helpers", () => {
  it("normalizes RGB hex input", () => {
    expect(normalizeHexColor("#00ffaa")).toBe("00FFAA");
  });

  it("splits whitespace separated specs", () => {
    expect(splitSpecs("W=FF0000   A=00FF00\nS=0000FF")).toEqual(["W=FF0000", "A=00FF00", "S=0000FF"]);
  });

  it("rejects null bytes before command execution", () => {
    expect(() => sanitizeArgs(["doctor", "bad\0value"])).toThrow(/null bytes/);
  });
});
