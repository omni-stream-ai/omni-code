# Desktop Bridge setup

The desktop welcome screen offers two ways to connect:

- **Install and enable auto-start** installs Bridge on this computer, starts it,
  enables startup at user sign-in, authorizes this desktop client, and opens the
  workspace. Closing the client leaves Bridge running.
- **Connect to an existing Bridge** uses the entered address and the existing
  host approval flow. This works for local and remote Bridges.

Installation runs only after the user clicks the install button. It downloads
the matching official GitHub release, checks its SHA-256 digest from the release
metadata before executing it, and checks service health before authorization.
The installer requires Bridge **0.8.0-beta.3 or later**. It prefers a compatible
stable release, then a compatible prerelease when the latest stable release is
too old or lacks the platform asset. It checks the executable's version before
installing or starting it, then verifies the authenticated workspace-agent API
before saving the connection. An old running service cannot complete setup even
when a newer executable exists on disk. An incompatible existing installation
is left in place, with an upgrade message and the Agent assistance entry.
It requires access to GitHub and a compatible
release for the operating system and CPU. A failed download or checksum leaves
the downloaded executable uninstalled. A retry reuses an already installed binary.

The executable and installer files live under `~/.omni-code-bridge`. Bridge data
uses `~/.omni-code`, shared with the standalone CLI. On Windows, `~` is the user
profile directory. The client stores its connection token in its existing
encrypted settings store. Only this client's authorization request is approved
automatically; other devices still require host approval.

An already running service on port 8787 that is not managed by the desktop
installer is left in place. Select **Connect to an existing Bridge** for it.
The desktop installer uses a separate service name from the standalone installer.

## Continue with Agent

After an installation failure, including an unsupported environment, the welcome
screen offers **Continue with Agent**. Assistance runs in the desktop client, so
it does not depend on a working Bridge or an installed agent CLI.

The client looks for enabled model providers in its encrypted local settings,
the local Bridge settings file, and the connected Bridge if accessible. A usable
configuration includes an API address and a specific model name. If none is
available, the client opens the model editor before making any model requests.
**Save and continue** stores the configuration locally and starts assistance;
canceling leaves the agent inactive. Existing model-provider settings are cached
locally for use when Bridge is unavailable. Chat Completions, Anthropic Messages,
and Responses (the existing Codex provider format) are supported.

The agent receives the failure category, available process error details, OS
information, installation paths, and recent Bridge log tails. Known credentials
and common secret patterns are redacted before diagnostics or command output go
to the model. Provider credentials are supplied to the configured endpoint only,
never included in the conversation. Model calls use the user's configured service.

Each proposed shell command is displayed with its purpose and requires the user
to click **Run this command**. Declined commands do not execute. Command output
returns to the agent for further analysis. Commands have a two-minute timeout;
each automatic turn is limited to 12 model requests. Closing assistance stops the
current command and cancels pending command approval.

The agent can retry the built-in installer or verify and authorize a Bridge it
repaired separately. Only a successful health check and desktop authorization
return a connection result to the welcome screen; a model's text alone cannot
mark setup complete. The client then saves the connection and opens the workspace.

## Startup and logs

Startup runs for the current user at sign-in, rather than before sign-in.
Administrator access is not required by this setup flow.

On Linux, new desktop windows write startup output to
`logs/desktop-window.log` in the application support directory (normally
`~/.local/share/com.omnistreamai.code/`). The log includes the child PID and a
first-frame message, so a running process can be distinguished from a rendered
window. Logs rotate at 1 MiB; no environment variables or authorization tokens
are added by the launcher.

| Platform | Startup registration | Logs |
| --- | --- | --- |
| Linux with a systemd user manager | `$XDG_CONFIG_HOME/systemd/user/omni-code-desktop-bridge.service` (default `~/.config`) | `journalctl --user -u omni-code-desktop-bridge` |
| Other Linux desktops | `$XDG_CONFIG_HOME/autostart/omni-code-desktop-bridge.desktop` | `~/.omni-code-bridge/bridge.log` |
| macOS | `~/Library/LaunchAgents/ai.omnistream.omni-code.bridge.plist` | `~/.omni-code-bridge/bridge.log` and `bridge-error.log` |
| Windows | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Omni Code Bridge.vbs` | `%USERPROFILE%\.omni-code-bridge\bridge.log` and `bridge-error.log` |

The macOS direct-distribution app runs without App Sandbox so it can install a
user LaunchAgent and execute the downloaded Bridge outside the app container.
This flow targets the project's desktop downloads, not a sandboxed App Store build.
Windows scripts use explicit Unicode encodings for non-ASCII user profile paths.

## Disable auto-start

On Linux with systemd:

```sh
systemctl --user disable --now omni-code-desktop-bridge.service
```

On other Linux desktops, remove the desktop entry listed above; this disables
startup at the next sign-in. On macOS, unload and disable the LaunchAgent:

```sh
launchctl bootout "gui/$(id -u)/ai.omnistream.omni-code.bridge"
launchctl disable "gui/$(id -u)/ai.omnistream.omni-code.bridge"
```

On Windows, disable **Omni Code Bridge** under startup apps, or remove its startup
file. Disabling a startup entry leaves the current process running until it exits
or the user signs out. Clicking the install button again enables startup again.
