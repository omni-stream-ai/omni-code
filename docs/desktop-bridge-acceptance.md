# Desktop Bridge acceptance evidence

Use independent initial states for installation, existing-service connection,
and failure recovery. A successful installation must not be reused as proof of
the existing-service connection flow.

Record the client source snapshot, client build hash, runtime image digest,
operating system and architecture. For the downloaded Bridge, also record the
resolved release tag, asset name and SHA-256. Freezing client sources does not
freeze GitHub's release metadata. Keep the original report when testing a fix.

## Fresh installation

Before opening the client, save a timestamped preparation log proving that the
disposable user profile has no Bridge installation, data, connection settings
or startup entry; Bridge is absent from PATH; no Bridge process is running; and
port 8787 is unused. Save the executed check results, not only the script source.
The preparation log must identify the same container or VM as the UI evidence.

Capture both connection choices, click installation once, and capture progress,
the connected workspace, and successful project creation. Save the installed
Bridge's --version output and /health response. Verify the authenticated
/workspace-agent response separately from generic service health. An
incompatible release must leave onboarding visible with the upgrade message.

## Startup after reboot

The current installer promises startup at **user sign-in**. Confirm this scope
before running the reboot case. Use a disposable desktop VM or a physical test
computer that can actually reboot and restore its login session.

Record the startup registration and boot ID after installation. Reboot, sign in,
and verify Bridge is running and healthy **before opening the client**. Save the
new boot ID, startup logs and a successful UI operation after connection.
Restarting a container or reopening the client does not prove this requirement.

## Existing Bridge

Start and health-check a compatible Bridge as the scenario's explicit
precondition. Open the client with independent connection settings, enter its
address, click authorization, approve that request on the host, then create a
project through the client. Capture the authorization and successful business
operation; do not invoke the install button in this scenario.

For a Linux new-window failure, retain the application support directory's
logs/desktop-window.log. Compare the child PID and first-frame message with
the actual screenshot and an input action; process existence alone is
insufficient. Verify the first window remains usable too.

## Failure and model configuration

Prepare separate profiles for these cases:

| Case | Required preparation | Required evidence |
| --- | --- | --- |
| Installation failure | Reproducible failure in the real download, verification or installation path; a usable model is configured | Failure message, Agent entry, and assistance continuing on the original problem |
| Unsupported platform | A platform or architecture the installer actually rejects; a usable model is configured | Unsupported message and the Agent flow; a network failure is not equivalent |
| No model | A real setup failure and no enabled usable model | Model editor appears before any model request; cancel leaves assistance inactive; valid save resumes the original problem |

Unit tests with mocked HTTP/model responses validate branching, but do not
replace evidence of a live provider-assisted recovery flow. Missing reboot or
provider prerequisites remain blocked and must be reported explicitly.
