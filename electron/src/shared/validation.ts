export function normalizeHexColor(value: string): string {
  const normalized = value.trim().replace(/^#/, "").toUpperCase();
  if (!/^[0-9A-F]{6}$/.test(normalized)) {
    throw new Error("Color must be a 6 digit hex value.");
  }
  return normalized;
}

export function splitSpecs(value: string): string[] {
  return value
    .split(/\s+/)
    .map((spec) => spec.trim())
    .filter(Boolean);
}

export function requireNonEmpty(value: string, label: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    throw new Error(`${label} is required.`);
  }
  return trimmed;
}

export function sanitizeArgs(args: string[]): string[] {
  return args.map((arg) => {
    if (arg.includes("\0")) {
      throw new Error("Command arguments must not contain null bytes.");
    }
    return arg;
  });
}
