# Binky — Agent Rules

## App Size (Non-negotiable)

Binky still ships legacy compression engines from the Dinky era (image/video encoders plus bundled **qpdf** and dylibs). Before adding **anything** — a framework, dependency, asset, font, or feature — mentally check its bundle size impact first.

**Rules:**
- Prefer Apple frameworks always: SwiftUI, Foundation, AppKit, UserNotifications, AVFoundation, etc. They're free — already in the OS, zero bundle cost.
- Never add an SPM or CocoaPods dependency without explicit approval from Derek AND a clear size justification.
- If a feature would meaningfully grow the binary (>100 KB), find a lighter native implementation or skip it.
- No Electron, no web views, no bundled runtimes, no embedded web engines. Ever.
- Assets (images, fonts) should be SVG/SF Symbols where possible. Raster assets must be justified.

**Current footprint reference:** Keep install weight honest vs Optimage / ImageOptim; slimming dead compression assets from the bundle is an ongoing goal now that v1 is organizer-first.

## Project Context

- macOS app, SwiftUI + macOS 26 (Tahoe), `.glassEffect()`, `.ultraThinMaterial`
- Built by Derek Castelli — full-time freelance web designer (Webflow/Figma) at heyderekj.com
- **v1 product:** Downloads inbox organizer (watch, classify, route, optional Finder tags, review bucket, history / undo moves).
- Legacy compression stack still present for backward compatibility paths; **UX is organizer-led**.
- GitHub: https://github.com/heyderekj/binky · Site: https://binkyfiles.com
