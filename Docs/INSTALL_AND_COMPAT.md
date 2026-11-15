# Creating vs installing

**Creation (supported by this app):** import images, layers, animate, preview, autosave, export a validated `.tendies`.

**Installing (NOT done by this app):** a `.tendies` must be written into PosterBoard's private container. A sandboxed app —
sideloaded or not — cannot do that. The community uses external tools:

| Tool | Where it runs | Notes (from their READMEs/news; not verified by us) |
|---|---|---|
| Nugget | computer (USB) | README: SparseRestore iOS 17.0–18.1.1, BookRestore iOS 18.2–26.1. |
| Pocket Poster | on-device | Needs a one-time Nugget run; reports of working on iOS 26 betas. |

**iOS 27 support for these tools is unknown to us** — check their release notes. TendieStudio ships no exploit and makes no claim
that any tool works on iOS 27. Use Share ▸ (Nugget/Pocket Poster/Files) from the export sheet.

## Device-testing checklist (nothing below could be verified in this environment)
1. Build with `xcodegen generate` + Xcode; sideload the IPA.
2. Apply `Samples/TendieStudio_TestPattern_14ProMax.tendies` with your tool on your iOS 27 phone: does it render? Is the layout correct on 430×932?
3. Export from the app; compare. Try each motion preset and the Record tool.
4. Scale animation and scale+rotation on one layer (unvalidated key paths).
5. Report iOS 27 behaviour so the app's warnings can be updated.
