# Omni Code Designs

![Omni Code Theme Board](./Omni_Code_Theme_Board.png)

This directory stores the shared OpenPencil design sources for Omni Code.

## Files

- `theme.op`: source of truth for shared design tokens, dark/light modes, and preview states.
- `main.op`: main screen draft aligned to the shared theme system.
- `Omni_Code_Theme_Board.png`: exported preview image from `theme.op`.

## Workflow

1. Update `theme.op` when the shared design system changes.
2. Run `node scripts/sync_op_theme.mjs` when `main.op` needs the latest theme block.
3. Re-export the preview PNG after meaningful visual changes and replace `Omni_Code_Theme_Board.png`.
