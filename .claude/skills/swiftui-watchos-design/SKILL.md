---
name: swiftui-watchos-design
description: Use when building or reviewing SwiftUI views, watchOS apps, or WidgetKit complications - encodes spacing, typography, colour, and native-component rules for a polished, native feel.
---

# SwiftUI / watchOS / WidgetKit design

Distilled from the SwiftUI Design Principles skill (context7 `/arjitj2/swiftui-design-principles`) plus Apple HIG. Apply these when writing or reviewing any SwiftUI, watchOS, or complication code.

## Spacing (base-4/8 grid)

Only use these values for padding and spacing: **4, 8, 12, 16, 20, 24, 32, 40, 48**. Arbitrary values (14, 26) create dissonance.

- Outer horizontal padding: 16-20pt.
- Between major sections: 24-32pt vertical.

## Typography

- **5 or fewer** distinct font sizes across the whole app AND widgets.
- Build hierarchy with **weight**, not just size.
- One `design` used consistently (e.g. `.default` or `.monospaced`, not mixed).
- `tracking` on uppercase labels only, at most 2 distinct values.
- Identifiers/years: `String(year)` or `.number.grouping(.never)`, never `"\(year)"` (locale can render "2,026").

## Colour

- Prefer **semantic** colours: `.primary`, `.secondary`, `.tertiary`, `Color(.systemBackground)`, `Color(.secondarySystemBackground)`, `Color(.separator)`. They adapt to light/dark and accessibility automatically.
- Avoid long `Color.white.opacity(N)` chains. Manual opacity: at most 2 values.
- Brand/tile colours (this app keys preset tiles off the source input) are fine, but keep them off the accent/selection colour so an active element is never confused with a selected control.

## Native components

- Cards: `Color(.secondarySystemBackground)`, `cornerRadius: 10`.
- Dividers: system `Divider()` with `.padding(.leading, 16)`.
- Grouped rows: `VStack(spacing: 0)` + Dividers, not hand-rolled.
- Toggles: use the built-in label, avoid `.labelsHidden()`.
- Navigation: `NavigationStack`, not a bare `ZStack`.
- Progress ring: background and foreground strokes share the **same** `lineWidth`.
- Exclusive choices: one `@State` enum, not several `Bool`s.

## WidgetKit / watchOS complications

- **Every** accessory view MUST declare `.containerBackground(... , for: .widget)` or watchOS renders the "!" placeholder.
- Home-screen widget background: `.containerBackground(.fill.tertiary, for: .widget)`.
- Lock-screen / watch circle: prefer `Gauge` with `.accessoryCircular`; bar: `Gauge` `.linearCapacity`.
- List every family in `.supportedFamilies([...])`; don't omit common ones. Accessory families: `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`, `.accessoryCorner`.
  - `accessoryInline` supports **SF Symbols only**, not custom images.
  - `accessoryCorner` = compact content in the corner + a curved label via `.widgetLabel(...)`.
- Dense visuals (100s of elements): use `Canvas`, not `ForEach` over hundreds of subviews.
- Timeline refresh rate must match data granularity; reload via `WidgetCenter.shared.reloadAllTimelines()` when shared state changes.
- App and widget share **one** data model (here: an App Group `UserDefaults`), not duplicate structs.
- Medium/large families share a consistent layout (header, body, footer) with 12pt internal padding.

## Anti-patterns

- No `minimumScaleFactor` hacks to force-fit text - fix the layout instead.
- Interactive editors present from payload state, not a `Bool` + separate data.
- Custom headers must not double-count the top safe-area inset.
- Preview and export share the same geometry model (pan/zoom/crop/layout).

## Fast iteration

Render SwiftUI to PNG headlessly with `ImageRenderer` in a `swift` script (see `scripts/render-*.swift`) to iterate on complication/widget looks without deploying to a device.

## Pre-ship checklist

1. Spacing all on the grid; outer padding 16-20pt; sections 24-32pt.
2. <=5 font sizes; one design; tracking on uppercase only.
3. Semantic colours; no long opacity chains.
4. Ring strokes equal width; cards 10pt radius; system Dividers.
5. Every widget family listed; `.containerBackground` present on all.
6. App and widget share one model; refresh matches data granularity.
7. `NavigationStack`, not bare `ZStack`; no `minimumScaleFactor` hacks.
