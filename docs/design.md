# Design System

## Status: unresolved — resolve before building UI

The original brief names "DesignMD" as the design system to follow but
doesn't specify where it lives. Before writing any screen:

1. Search this repo for a design system — a `design/` folder, a markdown
   spec, a Figma link in the README, a token file (`design_tokens.json`,
   a `theme.dart`), or a referenced package.
2. If found: inspect it fully — typography scale, color palette, spacing
   scale, button/card/nav/dialog components, icon set, empty/loading/error
   states — and use it exactly as specified. Do not invent a competing
   system.
3. If genuinely not found anywhere: say so explicitly in your report, and
   build against the fallback direction below instead of guessing at what
   "DesignMD" might mean.

## Fallback direction (only if no design system is found)

Quiet confidence, not an AI dashboard.

- **Typography**: one serif or humanist sans for a title/display size,
  a clean system sans for body text. Generous line height. Few weights.
- **Color**: a restrained neutral palette (warm off-white / near-black,
  or a calm dark mode), one accent color used sparingly — mainly for the
  Think button and active states.
- **Spacing**: generous whitespace over dense layouts. Nothing should feel
  like a form.
- **Components**: minimal chrome. Avoid heavy shadows, gradients, and
  rounded-everything. Cards should be rare, not the default container.
- **The Think button**: the single most important visual element on the
  home screen. It should be unmistakable and calm at once — not flashy,
  not buried among other controls.
- **Motion**: subtle only. A gentle waveform during active thinking, soft
  transitions between screens. Nothing that draws attention to itself.
- **States**: every screen needs a considered empty state, loading state,
  and error state — not a spinner and not a stack trace.

This fallback exists so implementation isn't blocked — it is explicitly
a stand-in, not a decision to keep if a real design system turns up later.
