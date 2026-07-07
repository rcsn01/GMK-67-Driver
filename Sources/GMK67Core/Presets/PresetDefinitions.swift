import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

let keyNameAliases: [String: String] = [
    "escape": "esc",
    "delete": "del",
    "equal": "=",
    "equals": "=",
    "minus": "-",
    "dash": "-",
    "leftbracket": "[",
    "rightbracket": "]",
    "lbracket": "[",
    "rbracket": "]",
    "semicolon": ";",
    "quote": "'\"",
    "apostrophe": "'\"",
    "backslash": "\\|",
    "pipe": "\\|",
    "comma": "<",
    "period": ">",
    "dot": ">",
    "slash": "?",
    "pgup": "page up",
    "pageup": "page up",
    "pgdn": "page down",
    "pagedown": "page down",
    "return": "enter",
    "cmd": "win",
    "command": "win",
    "option": "alt",
    "ctrl": "control"
]

let parseableSpecTargetAliases: [String: String] = [
    "=": "equal",
    "[": "lbracket",
    "]": "rbracket",
    ";": "semicolon",
    "'\"": "quote",
    "\\|": "backslash",
    "<": "comma",
    ">": "period",
    "?": "slash",
    "page up": "pageup",
    "page down": "pagedown",
    "←": "left",
    "↓": "down",
    "↑": "up",
    "→": "right"
]

let hidUsageAliases: [String: UInt8] = [
    "esc": 0x29,
    "escape": 0x29,
    "backspace": 0x2A,
    "tab": 0x2B,
    "enter": 0x28,
    "return": 0x28,
    "space": 0x2C,
    "delete": 0x4C,
    "del": 0x4C,
    "insert": 0x49,
    "ins": 0x49,
    "home": 0x4A,
    "end": 0x4D,
    "pageup": 0x4B,
    "pgup": 0x4B,
    "pagedown": 0x4E,
    "pgdn": 0x4E,
    "arrowright": 0x4F,
    "right": 0x4F,
    "arrowleft": 0x50,
    "left": 0x50,
    "arrowdown": 0x51,
    "down": 0x51,
    "arrowup": 0x52,
    "up": 0x52,
    "f1": 0x3A,
    "f2": 0x3B,
    "f3": 0x3C,
    "f4": 0x3D,
    "f5": 0x3E,
    "f6": 0x3F,
    "f7": 0x40,
    "f8": 0x41,
    "f9": 0x42,
    "f10": 0x43,
    "f11": 0x44,
    "f12": 0x45
]

let preferredHIDUsageNames: [UInt8: String] = [
    0x28: "enter",
    0x29: "esc",
    0x2A: "backspace",
    0x2B: "tab",
    0x2C: "space",
    0x3A: "f1",
    0x3B: "f2",
    0x3C: "f3",
    0x3D: "f4",
    0x3E: "f5",
    0x3F: "f6",
    0x40: "f7",
    0x41: "f8",
    0x42: "f9",
    0x43: "f10",
    0x44: "f11",
    0x45: "f12",
    0x49: "insert",
    0x4A: "home",
    0x4B: "pageup",
    0x4C: "del",
    0x4D: "end",
    0x4E: "pagedown",
    0x4F: "right",
    0x50: "left",
    0x51: "down",
    0x52: "up"
]

let modifierNameByEncodedUsage: [UInt8: String] = [
    0x01: "control",
    0x02: "shift",
    0x04: "alt",
    0x08: "win",
    0x10: "control",
    0x20: "shift",
    0x40: "alt",
    0x80: "win"
]

let modifierUsageByEncodedUsage: [UInt8: UInt8] = [
    0x01: 0xE0,
    0x02: 0xE1,
    0x04: 0xE2,
    0x08: 0xE3,
    0x10: 0xE4,
    0x20: 0xE5,
    0x40: 0xE6,
    0x80: 0xE7
]

let rgbPresetDefinitions: [RGBPresetDefinition] = [
    RGBPresetDefinition(name: "off", title: "Off", description: "Turn all mapped physical key LEDs off.", fill: "000000", assignments: []),
    RGBPresetDefinition(name: "white", title: "White", description: "Set all mapped physical keys to white.", fill: "FFFFFF", assignments: []),
    RGBPresetDefinition(name: "red", title: "Red", description: "Set all mapped physical keys to red.", fill: "FF0000", assignments: []),
    RGBPresetDefinition(name: "blue", title: "Blue", description: "Set all mapped physical keys to blue.", fill: "0000FF", assignments: []),
    RGBPresetDefinition(name: "wasd", title: "WASD", description: "Highlight WASD and arrow keys for games.", fill: "101018", assignments: [
        "W=FF3B30", "A=FFCC00", "S=34C759", "D=00C7BE",
        "up=5E5CE6", "left=FFCC00", "down=34C759", "right=00C7BE",
        "shift=FF2D55", "space=FFFFFF"
    ]),
    RGBPresetDefinition(name: "arrows", title: "Arrows", description: "Dim board with bright navigation keys.", fill: "05070A", assignments: [
        "up=FFFFFF", "left=FFCC00", "down=34C759", "right=00C7BE",
        "page up=AF52DE", "page down=5E5CE6", "del=FF3B30"
    ]),
    RGBPresetDefinition(name: "coding", title: "Coding", description: "Quiet base with syntax-colored punctuation and modifiers.", fill: "151515", assignments: [
        "esc=FF453A", "tab=64D2FF", "Caps=BF5AF2", "enter=30D158",
        "[=FFD60A", "]=FFD60A", ";=FF9F0A", "\\|=FFD60A",
        "control=64D2FF", "alt=64D2FF", "space=FFFFFF"
    ]),
    RGBPresetDefinition(name: "rainbow", title: "Rainbow Rows", description: "Simple row-based rainbow layout.", fill: "000000", assignments: [
        "esc=FF3B30", "1=FF3B30", "2=FF453A", "3=FF9F0A", "4=FFCC00", "5=FFD60A", "6=34C759", "7=30D158", "8=00C7BE", "9=64D2FF", "0=0A84FF", "-=5E5CE6", "equal=BF5AF2", "backspace=FF2D55",
        "tab=FF9F0A", "Q=FFCC00", "W=FFD60A", "E=34C759", "R=30D158", "T=00C7BE", "Y=64D2FF", "U=0A84FF", "I=5E5CE6", "O=BF5AF2", "P=FF2D55",
        "Caps=34C759", "A=30D158", "S=00C7BE", "D=64D2FF", "F=0A84FF", "G=5E5CE6", "H=BF5AF2", "J=FF2D55", "K=FF3B30", "L=FF9F0A", "enter=FFD60A",
        "shift=5E5CE6", "Z=BF5AF2", "X=FF2D55", "C=FF3B30", "V=FF9F0A", "B=FFCC00", "N=FFD60A", "M=34C759", "up=64D2FF",
        "control=0A84FF", "win=5E5CE6", "alt=BF5AF2", "space=FFFFFF", "fn=5E5CE6", "left=FFCC00", "down=34C759", "right=00C7BE"
    ]),
    RGBPresetDefinition(name: "ocean", title: "Ocean", description: "Blue and cyan board preset.", fill: "001E3C", assignments: [
        "W=00C7BE", "A=64D2FF", "S=0A84FF", "D=5E5CE6",
        "space=64D2FF", "enter=00C7BE", "esc=0A84FF"
    ]),
    RGBPresetDefinition(name: "sunset", title: "Sunset", description: "Warm orange, red, and purple board preset.", fill: "2B1028", assignments: [
        "esc=FF453A", "1=FF3B30", "2=FF453A", "3=FF9F0A", "4=FFCC00",
        "W=FF9F0A", "A=FFCC00", "S=FF453A", "D=BF5AF2",
        "space=FFCC00", "enter=FF9F0A"
    ]),
    RGBPresetDefinition(name: "green", title: "Green", description: "Set all mapped physical keys to green.", fill: "00FF00", assignments: []),
    RGBPresetDefinition(name: "purple", title: "Purple", description: "Set all mapped physical keys to purple.", fill: "8000FF", assignments: []),
    RGBPresetDefinition(name: "cyan", title: "Cyan", description: "Set all mapped physical keys to cyan.", fill: "00FFFF", assignments: []),
    RGBPresetDefinition(name: "orange", title: "Orange", description: "Set all mapped physical keys to orange.", fill: "FF6A00", assignments: []),
    RGBPresetDefinition(name: "pink", title: "Pink", description: "Set all mapped physical keys to pink.", fill: "FF2D8A", assignments: []),
    RGBPresetDefinition(name: "gold", title: "Gold", description: "Set all mapped physical keys to warm gold.", fill: "FFB000", assignments: []),
    RGBPresetDefinition(name: "fire", title: "Fire", description: "Ember base with hot reds, oranges, and yellows across the middle rows.", fill: "3A0A00", assignments: [
        "esc=FF3B30", "1=FF453A", "2=FF6A00", "3=FF9F0A", "4=FFCC00", "5=FFD60A", "6=FFCC00", "7=FF9F0A", "8=FF6A00", "9=FF453A", "0=FF3B30",
        "Q=FF6A00", "W=FF9F0A", "E=FFCC00", "R=FF9F0A", "T=FF6A00",
        "A=FF453A", "S=FF6A00", "D=FF9F0A", "F=FF6A00",
        "space=FF9F0A", "enter=FF453A"
    ]),
    RGBPresetDefinition(name: "ice", title: "Ice", description: "Frozen blue base with icy white and cyan highlights.", fill: "021B33", assignments: [
        "esc=FFFFFF", "tab=64D2FF", "Caps=64D2FF", "shift=64D2FF",
        "Q=BDEBFF", "W=FFFFFF", "E=BDEBFF",
        "A=64D2FF", "S=FFFFFF", "D=64D2FF",
        "space=BDEBFF", "enter=FFFFFF",
        "up=64D2FF", "left=64D2FF", "down=64D2FF", "right=64D2FF"
    ]),
    RGBPresetDefinition(name: "forest", title: "Forest", description: "Deep green base with mossy and amber highlights.", fill: "05230D", assignments: [
        "esc=FFD60A", "W=34C759", "A=30D158", "S=34C759", "D=30D158",
        "space=A3E635", "enter=34C759",
        "up=A3E635", "left=34C759", "down=30D158", "right=34C759"
    ]),
    RGBPresetDefinition(name: "matrix", title: "Matrix", description: "Black board with cascading green code columns.", fill: "000000", assignments: [
        "1=003B00", "Q=00FF41", "A=008F11", "Z=003B00",
        "3=008F11", "E=003B00", "D=00FF41", "C=008F11",
        "5=00FF41", "T=008F11", "G=003B00", "B=00FF41",
        "7=003B00", "U=00FF41", "J=008F11", "M=003B00",
        "9=008F11", "O=003B00", "L=00FF41",
        "-=00FF41", "[=008F11", ";=003B00",
        "space=003B00", "enter=00FF41"
    ]),
    RGBPresetDefinition(name: "aurora", title: "Aurora", description: "Night-sky base with green, teal, and violet aurora bands.", fill: "060B26", assignments: [
        "esc=34C759", "1=34C759", "2=30D158", "3=00C7BE", "4=64D2FF", "5=5E5CE6", "6=BF5AF2", "7=5E5CE6", "8=64D2FF", "9=00C7BE", "0=30D158",
        "Q=30D158", "W=00C7BE", "E=64D2FF", "R=5E5CE6", "T=BF5AF2",
        "space=00C7BE", "enter=34C759"
    ]),
    RGBPresetDefinition(name: "cyberpunk", title: "Cyberpunk", description: "Neon magenta and cyan city glow on a dark violet base.", fill: "14001F", assignments: [
        "esc=FF2D8A", "tab=00FFFF", "Caps=FF2D8A", "shift=00FFFF",
        "W=FF2D8A", "A=00FFFF", "S=FF2D8A", "D=00FFFF",
        "space=00FFFF", "enter=FF2D8A",
        "up=FFD60A", "left=FF2D8A", "down=00FFFF", "right=FFD60A"
    ]),
    RGBPresetDefinition(name: "pastel", title: "Pastel", description: "Soft lavender base with mint, peach, and baby-blue accents.", fill: "2E2440", assignments: [
        "esc=FFC2E2", "Q=C2FFD9", "W=FFE0C2", "E=C2E5FF", "R=E5C2FF",
        "A=C2E5FF", "S=FFC2E2", "D=C2FFD9",
        "space=E5C2FF", "enter=FFE0C2"
    ]),
    RGBPresetDefinition(name: "lava", title: "Lava", description: "Molten red base with bright magma cracks.", fill: "2A0000", assignments: [
        "tab=FF3B30", "Caps=FF6A00", "shift=FF3B30",
        "A=FF6A00", "S=FFD60A", "D=FF6A00", "F=FF3B30",
        "Z=FF3B30", "X=FF6A00", "C=FF3B30",
        "space=FF6A00", "enter=FFD60A"
    ])
]

let rgbLayoutPresetDefinitions: [RGBLayoutPresetDefinition] = [
    RGBLayoutPresetDefinition(
        name: "all",
        title: "All Keys",
        description: "Apply the selected theme's primary color to every mapped physical key.",
        fillRole: "primary",
        assignments: []
    ),
    RGBLayoutPresetDefinition(
        name: "wasd",
        title: "WASD",
        description: "Highlight WASD, arrows, Shift, and Space for games.",
        fillRole: "base",
        assignments: [
            "W=primary", "A=secondary", "S=tertiary", "D=quaternary",
            "up=primary", "left=secondary", "down=tertiary", "right=quaternary",
            "shift=accent", "space=text"
        ]
    ),
    RGBLayoutPresetDefinition(
        name: "arrows",
        title: "Arrows",
        description: "Highlight arrows and the compact navigation cluster.",
        fillRole: "base",
        assignments: [
            "up=text", "left=secondary", "down=tertiary", "right=quaternary",
            "page up=accent", "page down=primary", "del=danger"
        ]
    ),
    RGBLayoutPresetDefinition(
        name: "coding",
        title: "Coding",
        description: "Highlight coding punctuation, modifiers, Enter, and Space.",
        fillRole: "base",
        assignments: [
            "esc=danger", "tab=primary", "Caps=accent", "enter=tertiary",
            "[=secondary", "]=secondary", ";=quaternary", "\\|=secondary",
            "control=primary", "alt=primary", "space=text"
        ]
    ),
    RGBLayoutPresetDefinition(
        name: "rows",
        title: "Rows",
        description: "Apply the selected theme across keyboard rows.",
        fillRole: "base",
        assignments: [
            "esc=c1", "1=c1", "2=c2", "3=c3", "4=c4", "5=c5", "6=c6", "7=c7", "8=c8", "9=c9", "0=c10", "-=c11", "equal=c12", "backspace=danger",
            "tab=c3", "Q=c4", "W=c5", "E=c6", "R=c7", "T=c8", "Y=c9", "U=c10", "I=c11", "O=c12", "P=danger",
            "Caps=c6", "A=c7", "S=c8", "D=c9", "F=c10", "G=c11", "H=c12", "J=danger", "K=c1", "L=c3", "enter=c5",
            "shift=c11", "Z=c12", "X=danger", "C=c1", "V=c3", "B=c4", "N=c5", "M=c6", "up=c9",
            "control=c10", "win=c11", "alt=c12", "space=text", "fn=c11", "left=c4", "down=c6", "right=c8"
        ]
    )
]

let rgbColorThemeDefinitions: [RGBColorThemeDefinition] = [
    rgbColorThemeDefinition(name: "off", title: "Off", description: "Turn selected layout lighting off.", palette: ["000000"]),
    rgbColorThemeDefinition(name: "white", title: "White", description: "Clean white lighting.", palette: ["FFFFFF"]),
    rgbColorThemeDefinition(name: "red", title: "Red", description: "Solid red lighting.", palette: ["FF0000"]),
    rgbColorThemeDefinition(name: "green", title: "Green", description: "Solid green lighting.", palette: ["00FF00"]),
    rgbColorThemeDefinition(name: "blue", title: "Blue", description: "Solid blue lighting.", palette: ["0000FF"]),
    rgbColorThemeDefinition(name: "purple", title: "Purple", description: "Solid purple lighting.", palette: ["8000FF"]),
    rgbColorThemeDefinition(name: "cyan", title: "Cyan", description: "Solid cyan lighting.", palette: ["00FFFF"]),
    rgbColorThemeDefinition(name: "orange", title: "Orange", description: "Solid orange lighting.", palette: ["FF6A00"]),
    rgbColorThemeDefinition(name: "yellow", title: "Yellow", description: "Solid yellow lighting.", palette: ["FFFF00"]),
    rgbColorThemeDefinition(name: "pink", title: "Pink", description: "Solid pink lighting.", palette: ["FF2D8A"]),
    rgbColorThemeDefinition(name: "gold", title: "Gold", description: "Warm gold lighting.", palette: ["FFB000"]),
    rgbColorThemeDefinition(
        name: "rainbow",
        title: "Rainbow",
        description: "Bright multi-color theme.",
        base: "000000",
        palette: ["FF3B30", "FF9F0A", "FFCC00", "34C759", "00C7BE", "64D2FF", "0A84FF", "5E5CE6", "BF5AF2", "FF2D55", "FFD60A", "30D158"],
        text: "FFFFFF"
    ),
    rgbColorThemeDefinition(
        name: "ocean",
        title: "Ocean",
        description: "Blue and cyan lighting.",
        base: "001E3C",
        palette: ["00C7BE", "64D2FF", "0A84FF", "5E5CE6"],
        text: "BDEBFF"
    ),
    rgbColorThemeDefinition(
        name: "sunset",
        title: "Sunset",
        description: "Warm orange, red, and purple lighting.",
        base: "2B1028",
        palette: ["FF453A", "FF9F0A", "FFCC00", "BF5AF2"],
        text: "FFD60A"
    ),
    rgbColorThemeDefinition(
        name: "fire",
        title: "Fire",
        description: "Hot reds, oranges, and yellows.",
        base: "3A0A00",
        palette: ["FF3B30", "FF6A00", "FF9F0A", "FFCC00", "FFD60A"],
        text: "FFD60A"
    ),
    rgbColorThemeDefinition(
        name: "ice",
        title: "Ice",
        description: "Frozen blue, cyan, and white lighting.",
        base: "021B33",
        palette: ["64D2FF", "BDEBFF", "FFFFFF", "00C7BE"],
        text: "FFFFFF"
    ),
    rgbColorThemeDefinition(
        name: "forest",
        title: "Forest",
        description: "Deep green with mossy and amber highlights.",
        base: "05230D",
        palette: ["34C759", "30D158", "A3E635", "FFD60A"],
        text: "A3E635"
    ),
    rgbColorThemeDefinition(
        name: "matrix",
        title: "Matrix",
        description: "Black base with green code tones.",
        base: "000000",
        palette: ["00FF41", "008F11", "003B00", "34C759"],
        text: "00FF41"
    ),
    rgbColorThemeDefinition(
        name: "aurora",
        title: "Aurora",
        description: "Green, teal, blue, and violet bands.",
        base: "060B26",
        palette: ["34C759", "30D158", "00C7BE", "64D2FF", "5E5CE6", "BF5AF2"],
        text: "BDEBFF"
    ),
    rgbColorThemeDefinition(
        name: "cyberpunk",
        title: "Cyberpunk",
        description: "Neon magenta, cyan, and yellow.",
        base: "14001F",
        palette: ["FF2D8A", "00FFFF", "FFD60A", "BF5AF2"],
        text: "00FFFF"
    ),
    rgbColorThemeDefinition(
        name: "pastel",
        title: "Pastel",
        description: "Soft mint, peach, pink, blue, and lavender.",
        base: "2E2440",
        palette: ["C2FFD9", "FFE0C2", "FFC2E2", "C2E5FF", "E5C2FF"],
        text: "FFFFFF"
    ),
    rgbColorThemeDefinition(
        name: "lava",
        title: "Lava",
        description: "Molten red with bright magma highlights.",
        base: "2A0000",
        palette: ["FF3B30", "FF6A00", "FFD60A", "FF9F0A"],
        text: "FFD60A"
    )
]

let keymapPresetDefinitions: [KeymapPresetDefinition] = [
    KeymapPresetDefinition(name: "caps-esc", title: "Caps to Esc", description: "Map Caps Lock to Escape.", remaps: ["Caps=esc"]),
    KeymapPresetDefinition(name: "wasd-arrows", title: "WASD Arrows", description: "Map WASD to arrow keys.", remaps: ["W=up", "A=left", "S=down", "D=right"]),
    KeymapPresetDefinition(name: "vim-arrows", title: "Vim Arrows", description: "Map HJKL to left/down/up/right.", remaps: ["H=left", "J=down", "K=up", "L=right"]),
    KeymapPresetDefinition(name: "gaming-layer", title: "Gaming Layer", description: "Caps to Esc and WASD to arrows.", remaps: ["Caps=esc", "W=up", "A=left", "S=down", "D=right"]),
    KeymapPresetDefinition(name: "editing-shortcuts", title: "Editing Shortcuts", description: "Map navigation cluster keys to copy, paste, undo, and redo.", remaps: ["page up=C:control", "page down=V:control", "del=Z:control", "backspace=Y:control"]),
    KeymapPresetDefinition(name: "function-row", title: "Function Row", description: "Map number keys 1-0, minus, and equals to F1-F12.", remaps: ["1=f1", "2=f2", "3=f3", "4=f4", "5=f5", "6=f6", "7=f7", "8=f8", "9=f9", "0=f10", "-=f11", "equal=f12"]),
    KeymapPresetDefinition(name: "navigation-cluster", title: "Navigation Cluster", description: "Map bracket and punctuation keys to home/end/page navigation.", remaps: ["[=home", "]=end", ";=pageup", "'\"=pagedown"])
]

let lightingModePresetDefinitions: [LightingModePresetDefinition] = [
    LightingModePresetDefinition(name: "empty", title: "Empty", description: "Zeroed selector-03 lighting-mode table.", assignments: []),
    LightingModePresetDefinition(name: "wasd-steps", title: "WASD Steps", description: "Assign small mode bytes to WASD and arrows for controlled physical testing.", assignments: [
        "W=01", "A=02", "S=03", "D=04",
        "up=01", "left=02", "down=03", "right=04"
    ]),
    LightingModePresetDefinition(name: "nav-steps", title: "Navigation Steps", description: "Assign stepped mode bytes to navigation and editing keys.", assignments: [
        "home=01", "end=02", "pageup=03", "pagedown=04", "del=05", "backspace=06"
    ]),
    LightingModePresetDefinition(name: "row-steps", title: "Row Steps", description: "Assign repeated low mode bytes across the main alphanumeric rows.", assignments: [
        "Q=01", "W=02", "E=03", "R=04", "T=05", "Y=06", "U=07", "I=08", "O=09", "P=0A",
        "A=01", "S=02", "D=03", "F=04", "G=05", "H=06", "J=07", "K=08", "L=09",
        "Z=01", "X=02", "C=03", "V=04", "B=05", "N=06", "M=07"
    ])
]

let lightingEffectDefinitions: [LightingEffectDefinition] = [
    // The GMK67 SQLite profile stores these as t_light_data.mode rows 1...20.
    // The English language file also contains Inwards/Floweriness labels, but
    // this board's bundled DB has no backing t_light_data rows for modes 21/22.
    LightingEffectDefinition(name: "static", title: "Static", value: 0x01, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 10, aliases: ["solid", "steady"], summary: "Steady lighting without animation."),
    LightingEffectDefinition(name: "single-on", title: "SingleOn", value: 0x02, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 5, byte7: 9, aliases: ["lit-up", "reactive-on", "key-up"], summary: "Pressed keys light up, then fade."),
    LightingEffectDefinition(name: "single-off", title: "SingleOff", value: 0x03, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 10, aliases: ["lit-down", "reactive-off", "key-off"], summary: "Board stays lit; pressed keys go dark, then recover."),
    LightingEffectDefinition(name: "glittering", title: "Glittering", value: 0x04, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 12, byte7: 5, aliases: ["glitter", "sparkle", "starlight", "twinkle"], summary: "Random keys twinkle like starlight."),
    LightingEffectDefinition(name: "falling", title: "Falling", value: 0x05, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 10, byte7: 6, aliases: ["rain", "raindrop", "matrix-rain"], summary: "Lights fall down the board like rain."),
    LightingEffectDefinition(name: "colourful", title: "Colourful", value: 0x06, colorType: 1, red: 255, green: 0, blue: 0, byte5: 0, byte6: 15, byte7: 10, aliases: ["colorful", "rainbow", "multicolor"], summary: "Whole board cycles through many colors."),
    LightingEffectDefinition(name: "breath", title: "Breath", value: 0x07, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 6, aliases: ["breathing", "pulse-fade", "fade"], summary: "Whole board fades in and out slowly."),
    LightingEffectDefinition(name: "spectrum", title: "Spectrum", value: 0x08, colorType: 1, red: 255, green: 0, blue: 0, byte5: 0, byte6: 15, byte7: 10, aliases: ["spectrum-cycle", "color-cycle", "hue-cycle"], summary: "Whole board steps through the color spectrum."),
    LightingEffectDefinition(name: "outward", title: "Outward", value: 0x09, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 8, aliases: ["radiate", "outwards"], summary: "Light radiates outward from the center."),
    LightingEffectDefinition(name: "scrolling", title: "Scrolling", value: 0x0A, colorType: 0, red: 255, green: 255, blue: 255, byte5: 2, byte6: 15, byte7: 10, aliases: ["wave", "wave-right", "flow-wave"], summary: "A wave of color scrolls across the board."),
    LightingEffectDefinition(name: "rolling", title: "Rolling", value: 0x0B, colorType: 0, red: 255, green: 255, blue: 255, byte5: 1, byte6: 15, byte7: 10, aliases: ["roll", "wave-down"], summary: "Bands of light roll across the rows."),
    LightingEffectDefinition(name: "rotating", title: "Rotating", value: 0x0C, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 10, aliases: ["rotate", "spiral", "windmill"], summary: "Light rotates around the board."),
    LightingEffectDefinition(name: "explode", title: "Explode", value: 0x0D, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 10, aliases: ["explosion", "burst"], summary: "Keypresses burst light outward."),
    LightingEffectDefinition(name: "launch", title: "Launch", value: 0x0E, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 5, aliases: ["laser", "shoot"], summary: "Keypresses launch a beam across the row."),
    LightingEffectDefinition(name: "ripples", title: "Ripples", value: 0x0F, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 7, aliases: ["ripple", "water", "rings"], summary: "Keypresses ripple outward in rings."),
    LightingEffectDefinition(name: "flowing", title: "Flowing", value: 0x10, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 10, aliases: ["flow", "stream", "aurora"], summary: "Colors flow smoothly across the board."),
    LightingEffectDefinition(name: "pulsating", title: "Pulsating", value: 0x11, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 15, aliases: ["pulse", "heartbeat"], summary: "Board pulses rhythmically."),
    LightingEffectDefinition(name: "tilt", title: "Tilt", value: 0x12, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 10, aliases: ["slant", "diagonal"], summary: "Diagonal bands sweep the board."),
    LightingEffectDefinition(name: "shuttle", title: "Shuttle", value: 0x13, colorType: 0, red: 255, green: 255, blue: 255, byte5: 0, byte6: 15, byte7: 10, aliases: ["bounce", "ping-pong"], summary: "Light shuttles back and forth."),
    LightingEffectDefinition(name: "led-off", title: "LED Off", value: 0x14, colorType: 1, red: 255, green: 0, blue: 0, byte5: 0, byte6: 15, byte7: 10, aliases: ["off", "lights-off", "dark"], summary: "Turn all lighting off.")
]

let combinedProfilePresetDefinitions: [CombinedProfilePresetDefinition] = [
    CombinedProfilePresetDefinition(name: "gaming", title: "Gaming", description: "WASD lighting with Caps as Esc and WASD remapped to arrows.", rgbPreset: "wasd", keymapPreset: "gaming-layer"),
    CombinedProfilePresetDefinition(name: "navigation", title: "Navigation", description: "Dim board with navigation lighting and HJKL arrow remaps.", rgbPreset: "arrows", keymapPreset: "vim-arrows"),
    CombinedProfilePresetDefinition(name: "coding", title: "Coding", description: "Coding lighting with Caps mapped to Esc.", rgbPreset: "coding", keymapPreset: "caps-esc"),
    CombinedProfilePresetDefinition(name: "editing", title: "Editing", description: "Coding lighting with copy, paste, undo, and redo remaps.", rgbPreset: "coding", keymapPreset: "editing-shortcuts"),
    CombinedProfilePresetDefinition(name: "ocean-rgb", title: "Ocean RGB", description: "Ocean lighting without key remaps.", rgbPreset: "ocean", keymapPreset: nil),
    CombinedProfilePresetDefinition(name: "lights-off", title: "Lights Off", description: "Turn mapped LEDs off without changing keymaps.", rgbPreset: "off", keymapPreset: nil)
]

func keyLookupToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
}

func keyByName(_ name: String) -> KeyItem? {
    guard let keys = try? loadKeyboardLayout() else { return nil }
    let normalized = name.lowercased()
    if let key = keys.first(where: { $0.name.lowercased() == normalized || $0.desc.lowercased() == normalized }) {
        return key
    }

    let lookupToken = keyLookupToken(name)
    guard let alias = keyNameAliases[lookupToken] else {
        guard let usage = hidUsageAliases[lookupToken] else { return nil }
        return keys.first { $0.code == Int(usage) }
    }
    let normalizedAlias = alias.lowercased()
    return keys.first {
        $0.name.lowercased() == normalizedAlias || $0.desc.lowercased() == normalizedAlias
    }
}

func keyByArgument(_ argument: String) throws -> KeyItem {
    if let key = keyByName(argument) {
        return key
    }

    let normalized = argument.lowercased().replacingOccurrences(of: "0x", with: "")
    let radix = argument.lowercased().hasPrefix("0x") ? 16 : 10
    if let code = Int(normalized, radix: radix),
       let key = (try? loadKeyboardLayout())?.first(where: { $0.code == code || $0.keyIndex == code }) {
        return key
    }

    throw DriverError.invalidArgument("Unknown key: \(argument)")
}

func lightTargetByArgument(_ argument: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> (lightIndex: Int, label: String) {
    let normalized = argument.lowercased().replacingOccurrences(of: "0x", with: "")
    if argument.lowercased().hasPrefix("0x"), let parsed = Int(normalized, radix: 16) {
        guard parsed >= 0, parsed <= 0x8F else {
            throw DriverError.invalidArgument("Light index must be between 0x00 and 0x8F.")
        }
        return (parsed, keyMap[parsed]?.name ?? "light 0x\(String(format: "%02X", parsed))")
    }

    if let key = keyByName(argument) {
        return (key.lightIndex, key.name)
    }

    if let parsed = Int(argument), parsed >= 0, parsed <= 0x8F, keyMap[parsed] != nil {
        return (parsed, keyMap[parsed]?.name ?? "light \(parsed)")
    }

    throw DriverError.invalidArgument("Unknown key or light index: \(argument)")
}

func parseRGBAssignmentSpec(_ spec: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> RGBAssignment {
    let assignment = spec.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard assignment.count == 2, !assignment[0].isEmpty, !assignment[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid RGB spec '\(spec)'. Use key=rrggbb, for example W=FF0000.")
    }
    let color = try parseHexBytes(String(assignment[1]))
    guard color.count == 3 else {
        throw DriverError.invalidArgument("RGB color must be exactly three bytes in '\(spec)'.")
    }
    let target = try lightTargetByArgument(String(assignment[0]), keyMap: keyMap)
    return RGBAssignment(lightIndex: target.lightIndex, label: target.label, color: color)
}

func parseRGBAssignmentSpecs(_ specs: [String], keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> [RGBAssignment] {
    guard !specs.isEmpty else {
        throw DriverError.invalidArgument("At least one RGB assignment is required.")
    }
    let assignments = try specs.map { try parseRGBAssignmentSpec($0, keyMap: keyMap) }
    var seenLightIndices = Set<Int>()
    for assignment in assignments {
        guard seenLightIndices.insert(assignment.lightIndex).inserted else {
            throw DriverError.invalidArgument("Duplicate RGB target in assignment list: \(assignment.label)")
        }
    }
    return assignments
}

func rgbPreset(named name: String) throws -> RGBPresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = rgbPresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown RGB preset '\(name)'. Run rgb-preset-list to see available presets.")
    }
    return preset
}

func rgbLayoutPreset(named name: String) throws -> RGBLayoutPresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = rgbLayoutPresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown RGB layout preset '\(name)'. Run rgb-layout-list to see available presets.")
    }
    return preset
}

func rgbColorTheme(named name: String) throws -> RGBColorThemeDefinition {
    let token = keyLookupToken(name)
    guard let theme = rgbColorThemeDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown RGB color theme '\(name)'. Run rgb-theme-list to see available themes.")
    }
    return theme
}

func keymapPreset(named name: String) throws -> KeymapPresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = keymapPresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown keymap preset '\(name)'. Run keymap-preset-list to see available presets.")
    }
    return preset
}

func lightingModePreset(named name: String) throws -> LightingModePresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = lightingModePresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown lighting-mode preset '\(name)'. Run lighting-mode-preset-list to see available presets.")
    }
    return preset
}

func lightingEffect(named name: String) throws -> LightingEffectDefinition {
    let token = keyLookupToken(name)
    guard let effect = lightingEffectDefinitions.first(where: { candidate in
        keyLookupToken(candidate.name) == token
            || keyLookupToken(candidate.title) == token
            || candidate.aliases.contains { keyLookupToken($0) == token }
    }) else {
        throw DriverError.invalidArgument("Unknown lighting effect '\(name)'. Run effect-list to see available effects and aliases.")
    }
    return effect
}

func combinedProfilePreset(named name: String) throws -> CombinedProfilePresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = combinedProfilePresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown profile preset '\(name)'. Run profile-preset-list to see available presets.")
    }
    return preset
}

func makeCombinedProfile(from preset: CombinedProfilePresetDefinition) throws -> CombinedProfile {
    let profile = CombinedProfile(
        format: "gmk67-profile",
        version: 1,
        name: preset.title,
        rgbPreset: preset.rgbPreset,
        keymapPreset: preset.keymapPreset
    )
    try validateCombinedProfile(profile)
    return profile
}

func makeEditableCombinedProfile(from preset: CombinedProfilePresetDefinition) throws -> CombinedProfile {
    let rgb = try rgbPreset(named: preset.rgbPreset)
    let keymapRemaps = try preset.keymapPreset.map { try keymapPreset(named: $0).remaps }
    let profile = CombinedProfile(
        format: "gmk67-profile",
        version: 1,
        name: preset.title,
        rgbPreset: preset.rgbPreset,
        keymapPreset: nil,
        rgbFill: rgb.fill,
        rgbAssignments: rgb.assignments.isEmpty ? nil : rgb.assignments,
        keymapRemaps: (keymapRemaps ?? []).isEmpty ? nil : keymapRemaps
    )
    try validateCombinedProfile(profile)
    return profile
}

func rgbPresetFrames(_ preset: RGBPresetDefinition) throws -> [[UInt8]] {
    let fillColor = try parseHexBytes(preset.fill)
    guard fillColor.count == 3 else {
        throw DriverError.invalidArgument("Preset \(preset.name) has an invalid fill color.")
    }
    let keyMap = keyMapByLightIndex()
    var frames = sampleRGBFrames()
    try applyRGBFill(fillColor, to: &frames, keyMap: physicalKeysByLightIndex())
    if !preset.assignments.isEmpty {
        let assignments = try parseRGBAssignmentSpecs(preset.assignments, keyMap: keyMap)
        try applyRGBAssignments(assignments, to: &frames)
    }
    return frames
}

func rgbThemedPreset(_ layout: RGBLayoutPresetDefinition, theme: RGBColorThemeDefinition) throws -> RGBPresetDefinition {
    let fill = try rgbColorHex(for: layout.fillRole, in: theme)
    let assignments = try layout.assignments.map { assignment in
        let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw DriverError.invalidArgument("Invalid RGB layout assignment '\(assignment)' in \(layout.name).")
        }
        let target = String(parts[0])
        let role = String(parts[1])
        return "\(target)=\(try rgbColorHex(for: role, in: theme))"
    }
    return RGBPresetDefinition(
        name: "\(layout.name)-\(theme.name)",
        title: "\(layout.title) / \(theme.title)",
        description: "\(layout.description) Theme: \(theme.description)",
        fill: fill,
        assignments: assignments
    )
}

func rgbThemedPresetFrames(layout: RGBLayoutPresetDefinition, theme: RGBColorThemeDefinition) throws -> [[UInt8]] {
    try rgbPresetFrames(try rgbThemedPreset(layout, theme: theme))
}

private func rgbColorThemeDefinition(
    name: String,
    title: String,
    description: String,
    base: String? = nil,
    palette: [String],
    text: String? = nil
) -> RGBColorThemeDefinition {
    let normalizedPalette = palette.isEmpty ? ["000000"] : palette.map { $0.uppercased() }
    let primary = normalizedPalette[0]
    let secondary = rgbPaletteColor(normalizedPalette, at: 1, fallback: primary)
    let tertiary = rgbPaletteColor(normalizedPalette, at: 2, fallback: secondary)
    let quaternary = rgbPaletteColor(normalizedPalette, at: 3, fallback: tertiary)
    let accent = rgbPaletteColor(normalizedPalette, at: 4, fallback: quaternary)
    let textColor = text?.uppercased() ?? primary
    var colors: [String: String] = [
        "base": (base ?? "000000").uppercased(),
        "primary": primary,
        "secondary": secondary,
        "tertiary": tertiary,
        "quaternary": quaternary,
        "accent": accent,
        "danger": normalizedPalette.last ?? primary,
        "text": textColor
    ]
    for index in 1...12 {
        colors["c\(index)"] = normalizedPalette[(index - 1) % normalizedPalette.count]
    }
    return RGBColorThemeDefinition(name: name, title: title, description: description, colors: colors)
}

private func rgbPaletteColor(_ palette: [String], at index: Int, fallback: String) -> String {
    palette.indices.contains(index) ? palette[index] : fallback
}

private func rgbColorHex(for role: String, in theme: RGBColorThemeDefinition) throws -> String {
    let token = keyLookupToken(role)
    guard let value = theme.colors.first(where: { keyLookupToken($0.key) == token })?.value.uppercased() else {
        throw DriverError.invalidArgument("RGB theme \(theme.name) does not define color role '\(role)'.")
    }
    let bytes = try parseHexBytes(value)
    guard bytes.count == 3 else {
        throw DriverError.invalidArgument("RGB theme \(theme.name) has invalid color \(value) for role '\(role)'.")
    }
    return value
}

func keymapPresetRemaps(_ preset: KeymapPresetDefinition) throws -> [KeymapRemap] {
    try parseKeymapRemapSpecs(preset.remaps)
}

func lightingModePresetAssignments(_ preset: LightingModePresetDefinition) throws -> [ByteAssignment] {
    guard !preset.assignments.isEmpty else { return [] }
    return try parseByteAssignmentSpecs(preset.assignments)
}

func lightingEffectAssignments(_ effect: LightingEffectDefinition) -> [ByteAssignment] {
    physicalKeysByLightIndex()
        .sorted { $0.key < $1.key }
        .map { lightIndex, key in
            ByteAssignment(index: lightIndex, label: key.name, value: effect.value)
        }
}

func printRGBPresetList() {
    print("RGB presets:")
    for preset in rgbPresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
    }
}

func printRGBLayoutPresetList() {
    print("RGB layout presets:")
    for preset in rgbLayoutPresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
    }
}

func printRGBColorThemeList() {
    print("RGB color themes:")
    for theme in rgbColorThemeDefinitions {
        print("  \(theme.name) - \(theme.title): \(theme.description)")
    }
}

func printRGBPreset(_ preset: RGBPresetDefinition) {
    print("\(preset.name) - \(preset.title)")
    print("  \(preset.description)")
    print("  fill=\(preset.fill)")
    if !preset.assignments.isEmpty {
        print("  assignments: \(preset.assignments.joined(separator: " "))")
    }
}

func printRGBPresetJSON(_ preset: RGBPresetDefinition) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(preset)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func printKeymapPresetList() {
    print("Keymap presets:")
    for preset in keymapPresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
        print("    \(preset.remaps.joined(separator: " "))")
    }
}

func printKeymapPreset(_ preset: KeymapPresetDefinition) {
    print("\(preset.name) - \(preset.title)")
    print("  \(preset.description)")
    if !preset.remaps.isEmpty {
        print("  remaps: \(preset.remaps.joined(separator: " "))")
    }
}

func printKeymapPresetJSON(_ preset: KeymapPresetDefinition) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(preset)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func printLightingModePresetList() {
    print("Lighting-mode presets:")
    for preset in lightingModePresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
        if !preset.assignments.isEmpty {
            print("    \(preset.assignments.joined(separator: " "))")
        }
    }
}

func printLightingEffectList() {
    print("GMK67 lighting effects from t_light_data mode rows:")
    for effect in lightingEffectDefinitions {
        print(String(
            format: "  %@ - %@: mode 0x%02X rgb=%02X%02X%02X colortype=%d byte5=%d byte6=%d byte7=%d",
            effect.name,
            effect.title,
            effect.value,
            effect.red,
            effect.green,
            effect.blue,
            effect.colorType,
            effect.byte5,
            effect.byte6,
            effect.byte7
        ))
    }
    print("These names come from the Windows language resource; the 20 mode IDs are confirmed by the GMK67 SQLite t_light_data rows.")
    print("Live animated apply uses the native 04 13 mode+color payload shape reverse-engineered from DeviceDriver.exe.")
}

func printEffectPresetList() {
    print("Built-in lighting effect names:")
    for effect in lightingEffectDefinitions {
        print("  \(effect.name) - \(effect.title): \(effect.summary)")
        if !effect.aliases.isEmpty {
            print("    aliases: \(effect.aliases.joined(separator: ", "))")
        }
    }
    print("Live animated effect selection uses the reverse-engineered native 04 13 mode+color payload.")
    print("Use lighting-effect-apply to send a mode, optional color, and DB-backed option bytes.")
}

func printCombinedProfilePresetList() {
    print("Profile presets:")
    for preset in combinedProfilePresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
        print("    rgb=\(preset.rgbPreset) keymap=\(preset.keymapPreset ?? "-")")
    }
}
