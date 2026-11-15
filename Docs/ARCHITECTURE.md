# Architecture

Swift 5 / SwiftUI, iOS 17+ (Liquid Glass via `#available(iOS 26)`, material fallback). **Zero third-party dependencies.**

| Layer | Files | Notes |
|---|---|---|
| Model | `Model/*` | `WallpaperProject` (Codable). Keyframe tracks per property; `AnimationBaker` samples tracks at 30 Hz; `LayerResolver` turns a layer into a platform-neutral description. |
| Render | `Render/WallpaperRenderer.swift` | Builds a real `CALayer` tree with `CAKeyframeAnimation`s from `ResolvedLayer`. Paused = `speed 0` + `timeOffset` (no per-frame work); playing is driven by the render server. |
| Export | `Export/*` | `CAMLWriter` emits the CAML dialect found in real files from the **same** `ResolvedLayer`s as the preview → preview = export. `TendiesExporter` assembles the ZIP with the verbatim template; `TendiesValidator` checks the result; `ZipArchive` is a dependency-free reader/writer. |
| Storage | `Storage/ProjectStore.swift` | `Application Support/TendieStudio/Projects/<uuid>.tsproj/{project.json,assets/,thumbnail.jpg}`; atomic writes; imports in `Imports/`. Files app visible via `UIFileSharingEnabled`. |
| Community | `Community/*` | Read-only client of CAPlayground's public JSON; offline cache; first-frame GIF thumbnails; GIFs streamed frame-by-frame with ImageIO. |
| Features | `Features/{Discover,Studio,Library}` | Thin SwiftUI views over `EditorModel` / `ProjectStore` / `CommunityService`. |

Design decisions
* **Bake easing/physics into samples** (30 Hz, ≤ 900 samples): only constructs proven in real files are emitted.
* **Local-first**: no network needed except Discover; no accounts, analytics or paid APIs.
* **Battery**: static aurora background, no timers while idle, playback by Core Animation, downsampled thumbnails, images re-encoded ≤ 2048 px.
* **Autosave**: 0.7 s debounce after any change + on backgrounding; undo stack of 60 snapshots.
* **Not used (yet):** Metal. Core Animation is what the wallpaper itself runs on; a Metal path wouldn't improve fidelity.

Editor interactions: drag/pinch/twist on canvas (centre snapping, 15° rotation snapping, haptics), ◆ keyframes at playhead,
draggable keyframes, per-keyframe easing, Repeat/Ping-pong, "Close loop", motion presets, and **Record**: arm it, drag a layer,
and the path becomes position keyframes that loop back to the start.
