# Agent Notes

- Before modifying any design asset or OpenPencil design draft, read [DESIGN.md](/home/junjie/code/omni-code/DESIGN.md) and follow its icon, theme token, radius, spacing, and design consistency rules.
- Web persistence must use browser storage, not `path_provider` file paths.
- Desktop/mobile persistence can continue to use local files where appropriate.
- Any setting or auth state that must survive page refresh in web should be stored through the web-specific store, not only `AppSettingsController`.
- Before adding new persisted state, check whether it needs a separate web implementation.
