export interface VisualKey {
  kind: "key";
  spec: string;
  label: string;
  width: number;
}

export interface VisualSpacer {
  kind: "spacer";
  width: number;
}

export type VisualKeyboardItem = VisualKey | VisualSpacer;

const key = (spec: string, label = spec, width = 38): VisualKey => ({ kind: "key", spec, label, width });
const spacer = (width: number): VisualSpacer => ({ kind: "spacer", width });

export const visualKeyboardRows: VisualKeyboardItem[][] = [
  [
    key("esc"),
    key("1"),
    key("2"),
    key("3"),
    key("4"),
    key("5"),
    key("6"),
    key("7"),
    key("8"),
    key("9"),
    key("0"),
    key("-"),
    key("equal", "="),
    key("backspace", "backspace", 86),
  ],
  [
    key("tab", "tab", 60),
    key("Q"),
    key("W"),
    key("E"),
    key("R"),
    key("T"),
    key("Y"),
    key("U"),
    key("I"),
    key("O"),
    key("P"),
    key("["),
    key("]"),
    key("\\|", "\\|", 60),
    key("del"),
  ],
  [
    key("Caps", "caps", 70),
    key("A"),
    key("S"),
    key("D"),
    key("F"),
    key("G"),
    key("H"),
    key("J"),
    key("K"),
    key("L"),
    key(";"),
    key("quote", "'\""),
    key("enter", "enter", 94),
    key("pageup", "pg up"),
  ],
  [
    key("0x49", "shift", 94),
    key("Z"),
    key("X"),
    key("C"),
    key("V"),
    key("B"),
    key("N"),
    key("M"),
    key("comma", "<"),
    key("period", ">"),
    key("slash", "?"),
    key("0x54", "shift", 70),
    key("up", "up"),
    key("pagedown", "pg dn"),
  ],
  [
    key("control", "ctrl", 48),
    key("win", "cmd", 48),
    key("0x5D", "alt", 48),
    key("space", "space", 286),
    key("0x5F", "alt", 48),
    key("fn", "fn", 48),
    spacer(4),
    key("left", "left"),
    key("down", "down"),
    key("right", "right"),
  ],
];
