# Contributing

Thanks for considering a contribution to Omni Code.

This project is still early and the public API may change. For large changes,
please open an issue first to discuss the problem, proposed behavior, and
implementation direction.

## Development

Flutter client:

```bash
flutter pub get
flutter analyze
```

## Pull Requests

Before opening a PR:

- Keep the change focused on one behavior or problem.
- Update documentation when setup, configuration, or user-visible behavior changes.
- Do not commit local secrets, signing files, Firebase credentials, build outputs, or IDE state.
- Include manual verification notes for client flows, push notification changes, or approval behavior.

## Security-Sensitive Changes

Changes around command execution, approval policy, bridge authentication, or
network exposure need extra care. Describe the threat model and failure behavior
in the PR so reviewers can evaluate the risk.
