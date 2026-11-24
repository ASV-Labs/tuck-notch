# UX design system

Tokens live in `Sources/TuckNotch/DesignSystem.swift` (`DS`).

| Token | Value | Increase Contrast |
|---|---|---|
| Exterior | #000000 | #000000 |
| Surface | #171717 | #1F1F1F |
| Elevated | #282828 | #3A3A3A |
| Text primary | #F5F5F7 | #FFFFFF |
| Text secondary | #A1A1AA | #D4D4D8 |
| Card stroke | none | white 45% |
| Accent / Live / Success / Warning / Danger | #0A84FF / #FF9F0A / #30D158 / #FFD60A / #FF453A | same |
| Spacing | 4 · 8 · 12 · 16 · 24 | |
| Radii | control 8 · card 14 · panel 22 · flare 6 | |
| Hit target | ≥ 28 × 28 pt | |
| Type | SF Pro: 15 semibold title, 13 body, 11 caption, 22 rounded metric | |
| Motion | island spring ≈ 250 ms (response 0.3, damping 0.86); content fade 200 ms; Reduce Motion → 120–180 ms fades, equalizer static | |

## Sizes
Expanded 480 pt wide (wider if the notch needs it), tab bar 36, content 236. Peek 400 × 132. Attention 400 × 76.

## Rules
- The exterior stays pure black; only the interior adapts.
- One shape morphs between states; content cross-fades. Nothing animates while dormant.
- Automatic updates (live, attention) never take keyboard focus. Only click/hotkey/menu do.
- Hover opens Peek, never Expanded. Hover is ignored while a mouse button is held and in presentation mode.
- Every control has a VoiceOver label; state changes are announced; ⌘1–⌘8, Space, Return, Esc work in the panel.
- Empty, loading (OCR), permission-denied and unsupported-source states each have copy.
