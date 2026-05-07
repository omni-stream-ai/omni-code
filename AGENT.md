# Agent Notes

- Web persistence must use browser storage, not `path_provider` file paths.
- Desktop/mobile persistence can continue to use local files where appropriate.
- Any setting or auth state that must survive page refresh in web should be stored through the web-specific store, not only `AppSettingsController`.
- Before adding new persisted state, check whether it needs a separate web implementation.
