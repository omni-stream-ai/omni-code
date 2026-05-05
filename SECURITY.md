# Security Policy

Omni Code connects a client app to a local desktop bridge that can interact with
command-line agents. Treat it as a security-sensitive tool.

## Supported Versions

The project is pre-1.0. Security fixes are handled on the default branch unless
a release process is introduced later.

## Reporting a Vulnerability

Please do not open a public issue for vulnerabilities that could expose secrets,
allow unauthorized bridge access, bypass approval policy, or execute commands.

Report privately to the repository owner through GitHub security advisories if
available. If that is not enabled, contact the maintainer through a private
channel listed on the GitHub profile.

Include:

- A clear description of the issue.
- Reproduction steps or a proof of concept.
- Affected platform and configuration.
- Expected impact and any suggested mitigation.

## Operational Guidance

- Do not expose the desktop bridge directly to the public internet.
- Use a strong `ECHO_MATE_BRIDGE_TOKEN`.
- Restrict allowed mobile client IDs with `ECHO_MATE_ALLOWED_CLIENT_IDS`.
- Keep `.env`, Firebase credentials, signing keys, and service account files out of Git.
- Treat AI approval as a conservative helper, not as the only safety boundary.
