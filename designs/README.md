# Omni Code Designs

![Omni Code Theme Board](./Omni_Code_Theme_Board.png)

![Omni Code Call Mode Wireframe](./call-mode-ui-wireframe.png)

This directory stores the maintained OpenPencil design sources for Omni Code.

## Files

- `theme.op`: shared tokens, preview states, and theme reference board.
- `main.op`: main app design draft that consumes the shared theme tokens.
- `call-page.op`: standalone voice call page concept based on the light, soft-glow mobile reference style.
- `Omni_Code_Theme_Board.png`: preview export for the shared theme board.
- `call-mode-ui-wireframe.png`: preview export for the main wireframe.
- `call-mode-ui-wireframe.svg`: vector export for the main wireframe.

## Workflow

1. Edit shared tokens in `designs/theme.op`.
2. Run `node scripts/sync_op_theme.mjs` to sync the shared theme block into `designs/main.op`.
3. Re-export the preview assets after meaningful visual changes.
