# Design Notes

## Scope

- This file only defines shared visual rules, token usage, and design-system constraints.
- Do not store feature-specific layouts, flow decisions, copy, or per-screen icon mappings here.
- One-off product decisions belong in the design file itself or the implementation, not in this document.

## Source Of Truth

- `designs/theme.op` is the source of truth for shared design tokens.
- Prefer semantic tokens before adding new raw values.
- In `designs/*.op`, colors and strokes should use token refs like `$--color-panel` instead of new hex values whenever possible.
- When a design file needs local token resolution, run `node scripts/sync_op_theme.mjs` to inject the shared theme block from `designs/theme.op`.

## Theme System

Shared token categories in `designs/theme.op`:

- Typography
- Radius
- Spacing
- Color

Current foundation tokens:

- Radius: `--radius-screen`, `--radius-card`, `--radius-tile`, `--radius-control`, `--radius-capsule`, `--radius-pill`
- Spacing: `--space-text-tight`, `--space-text-stack`, `--space-control-tight`, `--space-compact`, `--space-tile-y`, `--space-tile-x`, `--space-stack`, `--space-card`, `--space-block`, `--space-screen-x`, `--space-screen-bottom`, `--space-screen-top`

Rules:

- Reuse an existing semantic token before creating a new one.
- Add a new token only when a value represents a stable new role in the system, not a one-off exception.
- When a token is added in `theme.op`, update this document only if it changes the shared system, not just one screen.

## Color System

- Use semantic color tokens from `theme.op` rather than raw hex values.
- Keep token naming role-based, not page-based.
- Prefer a small set of reusable surfaces, text levels, and state colors over local special cases.
- Dark and light mode values should stay paired inside the same token instead of forking token names by mode.
- `--color-primary` is reserved for primary action fills and other solid emphasis surfaces. Do not use it as the default pure-text action color on light backgrounds.
- Pure text buttons, inline links, and low-chrome actionable labels should use `--color-accent-blue`.
- Keep `--color-signal` for product/status accents such as telemetry or sync, not the default text action color.

## Radius System

Use this scale for Omni Code OpenPencil drafts:

- Screen shell: `28` via `--radius-screen`
- Major card / panel: `14` via `--radius-card`
- Dense nested tile: `12` via `--radius-tile`
- Standard control / button / input: `10` via `--radius-control`
- Small capsule: `8` via `--radius-capsule`
- Full pill only: `999` via `--radius-pill`

Rules:

- Do not introduce new corner radii unless a component has a clear new semantic role.
- `12` is the midpoint for dense list rows and nested utility tiles, not the default card radius.
- `999` is only for pills, progress rails, and thin state markers.

## Spacing And Padding System

Use this spacing scale for Omni Code OpenPencil drafts:

- Micro text grouping: `1` via `--space-text-tight`, `2` via `--space-text-stack`
- Tight control spacing: `6` via `--space-control-tight`, `8` via `--space-compact`
- Dense tile vertical inset: `10` via `--space-tile-y`
- Dense tile horizontal inset and standard inline inset: `12` via `--space-tile-x`
- Default vertical stack: `12` via `--space-stack`
- Standard card padding and section gap: `14` via `--space-card`
- Comfortable block padding: `16` via `--space-block`
- Screen side / bottom inset: `18` via `--space-screen-x`, `--space-screen-bottom`
- Screen top offset: `28` via `--space-screen-top`

Preferred padding patterns:

- Screen shell: `[28, 18, 18, 18]`
- Standard card: `14` via `--space-card`
- Dense row / tile: `[10, 12]` via `[--space-tile-y, --space-tile-x]`
- Capsule / small badge: `[0, 12]` using `--space-tile-x` for horizontal inset

Preferred gap patterns:

- Text stacks inside one item: `1` or `2`
- Compact control clusters: `6`, `8`, or `10`
- Default vertical stack: `12`
- Major screen section separation: `14` or `16`

## Typography

- Use the theme typography tokens as the default source for display and body text.
- Preserve a small number of text roles with clear hierarchy rather than introducing many near-duplicate sizes.
- Use expressive typography at the system level, but keep usage consistent across screens once chosen.

## Icon System

- Keep icon style consistent with the product implementation.
- Do not mix unrelated icon families inside design assets.
- Favor semantic clarity over decoration.
- If an action reads clearly without an icon, omit the icon rather than adding noise.

## OpenPencil Limitation

- OpenPencil currently resolves color and stroke token refs reliably in `.op` files.
- `gap` and scalar `padding` token refs are reliable enough to use in design drafts.
- Radius, font family, and many padding-array cases are not as reliable as variable refs yet.
- Because of that, keep corner radii and array paddings aligned to the system scale above even if some values remain literal numbers in the file.

## Working Rule

- Before changing a design draft, align with the existing design system first: token roles, radius scale, spacing scale, typography, and icon style.
