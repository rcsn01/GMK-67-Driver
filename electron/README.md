# GMK67 Electron App

This is the side-by-side Electron migration for the GMK67 UI. The Swift `gmk67` CLI remains the macOS hardware backend in this phase.

## Development

```sh
cd electron
npm install
npm run dev
```

`npm run dev` runs `scripts/ensure-helper.mjs` before Electron starts. The script reuses `.build/debug/gmk67` when it is current and runs `swift build --product gmk67` only when the helper is missing or older than the Swift backend sources.

The main process runs the helper with `child_process.spawn`, never through a shell. Commands are serialized so HID reads and writes do not overlap. The helper cwd is `~/Library/Application Support/GMK67`, and `GMK67_RESOURCES_DIR` points at the repository `Resources` directory during development.

## Packaging

```sh
cd electron
npm run package:mac
```

`scripts/prepare-helper.mjs` builds `.build/debug/gmk67`, copies it to `electron/assets/bin/GMK67Helper`, and Forge copies it into `Contents/MacOS/GMK67Helper` for macOS packages. `Resources/vendor` is bundled as an extra resource.
