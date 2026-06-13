---
name: self-verify-prowl
description: Bootstrap-verify Prowl changes by launching a debug app with a dedicated PROWL_CLI_SOCKET and driving it from the current Prowl session. Use after implementing Prowl app, terminal, Active Agents, or CLI changes when Codex should validate behavior end-to-end in a separate Prowl instance, including opening worktrees, creating tabs, running commands or agent sessions, reading panes, and falling back to a single-window screenshot of the debug app when the prowl CLI is insufficient.
---

# Self Verify Prowl

## Overview

Use this skill to validate a Prowl change from inside Prowl itself: start a freshly built debug app, point it at a temporary CLI socket, and use `prowl` from the current session to drive that separate app instance.

Prefer `prowl` CLI operations because they are scriptable and leave useful evidence. When CLI coverage is not enough, fall back to a single-window screenshot of the debug app as a secondary check.

## When To Use

Use this after changes that affect:

- Prowl app behavior that needs a real running GUI instance.
- Terminal tabs, panes, focus, worktrees, or command routing.
- Active Agents detection or roster presentation.
- `ProwlCLI/`, CLI payloads, socket transport, or CLI docs.
- Workflows where one Prowl-hosted agent should verify another Prowl instance.

Do not use this as a replacement for unit tests, `make check`, `make build-app`, or CLI integration tests. It is an end-to-end manual validation layer on top of those checks.

## Preconditions

- Work from the Prowl repository root.
- Preserve unrelated user changes. Do not close or kill the user's normal Prowl app.
- If the CLI changed, build and use the repo CLI, usually `./.build/debug/prowl`.
- If the CLI did not change, an installed `prowl` may be usable, but the repo-built CLI keeps the app/CLI protocol aligned.
- For detailed CLI targeting and recipes, consult the dedicated `prowl-cli` skill first when needed.

## Launch A Separate App

Start the debug app with a dedicated socket so it does not fight the normal installed Prowl instance for the default socket:

```bash
socket="/tmp/prowl-self-verify-$$.sock"
PROWL_CLI_SOCKET="$socket" make run-app
```

Keep that command running in its own shell session. If plain `make run-app` reports a socket ownership problem, relaunch with a custom `PROWL_CLI_SOCKET`; the installed app may already own the standard socket.

When `PROWL_CLI_SOCKET` is set, CLI auto-launch is disabled. The debug app and every CLI invocation must use the same socket value.

## Drive With Prowl CLI

Use the new CLI when CLI behavior changed:

```bash
make build-cli
cli="./.build/debug/prowl"
```

Then operate the debug app through the custom socket:

```bash
PROWL_CLI_SOCKET="$socket" "$cli" open .
PROWL_CLI_SOCKET="$socket" "$cli" list --json
PROWL_CLI_SOCKET="$socket" "$cli" tab create --json
PROWL_CLI_SOCKET="$socket" "$cli" send --pane "$pane" 'printf "SELF_VERIFY:%s\n" "$PWD"' --capture --timeout 30 --json
PROWL_CLI_SOCKET="$socket" "$cli" read --pane "$pane" --last 80 --wait-stable --json
```

Prefer targeting by pane or tab UUIDs from JSON output. Avoid relying on titles when multiple Prowl instances or similar tabs exist.

## Run Observable Scenarios

Turn the change into one or more observable scenarios. Prefer small checks that prove the behavior directly:

- For command routing, run a command that prints the cwd, environment, or a unique marker.
- For tab, pane, focus, or worktree behavior, create an isolated tab or pane and inspect `list --json` before and after the action.
- For long-running task behavior, start a controlled command with visible output, then sample the pane with `read`.
- For agent-specific behavior, start a short agent session and use `agents --json` only when the changed behavior involves the Active Agents roster.

Example command scenario:

```bash
PROWL_CLI_SOCKET="$socket" "$cli" send --pane "$pane" \
  'printf "SELF_VERIFY:%s\n" "$PWD"' \
  --capture --timeout 30 --json

PROWL_CLI_SOCKET="$socket" "$cli" read --pane "$pane" --last 80 --wait-stable --json
```

Example long-running scenario:

```bash
PROWL_CLI_SOCKET="$socket" "$cli" send --pane "$pane" \
  'for i in 1 2 3; do echo "SELF_VERIFY_STEP:$i"; sleep 1; done' \
  --no-wait --json

PROWL_CLI_SOCKET="$socket" "$cli" read --pane "$pane" --last 120 --json
```

If the scenario uses another agent, keep it scoped and reversible. Short non-interactive agent tasks can finish before they are sampled; use an interactive session only when the behavior under test requires observing an active retained pane.

## Fallback Checks

`prowl` is the primary control surface, but it cannot verify every visual detail. Use a screenshot when CLI output cannot prove the behavior.

Capture only the debug app's window, not the whole screen. The current Prowl session usually sits in front of the debug instance, so a full-screen `screencapture -x` would show the wrong window. Resolve the debug app's window id from its PID and capture just that window:

```bash
mkdir -p /tmp/prowl-self-verify
pid="$(ps aux | grep "Debug/Prowl.app/Contents/MacOS/Prowl" | grep -v grep | awk '{print $2}' | head -1)"
cat > /tmp/prowl-self-verify/winid.swift <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1]) ?? -1
let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
  if let n = w[kCGWindowNumber as String] as? Int { print(n); break }
}
SWIFT
wid="$(swift /tmp/prowl-self-verify/winid.swift "$pid" | head -1)"
screencapture -o -l"$wid" /tmp/prowl-self-verify/prowl-debug-window.png
```

Match on the `Debug/Prowl.app` path so you target the debug instance, never the installed app. `screencapture -o -l<windowid>` grabs just that window without its shadow. Then use `view_image` or another image inspection tool to review it.

Browser or computer-use skills are useful for web and localhost targets, but do not provide reliable control over arbitrary macOS apps. Prefer the Prowl CLI first, then a single-window screenshot for visual gaps.

## Cleanup

Close tabs or panes created for verification:

```bash
PROWL_CLI_SOCKET="$socket" "$cli" tab close --tab "$tab" --force --json
```

Stop the `make run-app` session when validation is done. If you must terminate manually, target only the debug app launched from DerivedData and do not kill `/Applications/Prowl.app`:

```bash
pkill -f "DerivedData/.*/Debug/Prowl.app/Contents/MacOS/Prowl"
```

Remove the temporary files this skill created. The app never cleans up the custom socket or its lock: `CLISocketServer` only `unlink`s the socket on a clean `stop()` and never unlinks the `.lock` file at all, so a killed debug app leaves both `$socket` and `$socket.lock` behind. Delete them yourself, along with any screenshots:

```bash
rm -f "$socket" "$socket.lock"
rm -rf /tmp/prowl-self-verify
```

## Report Results

In the final report, include:

- The socket path used for the debug app.
- Which CLI binary was used and why.
- The concrete CLI operations and agent tasks performed.
- The relevant observed app or agent states.
- Any single-window screenshot evidence.
- Cleanup performed and any remaining limitations.
