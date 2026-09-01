---
name: sync-pull
description: "Synchronize cmux workspaces and preferences from the production /Applications/cmux.app installation into the current tagged local dev build, then relaunch the dev build. Use when the user asks to pull, import, or sync cmux state from production."
---

# Sync Pull

Import the production cmux state into the current tagged local dev build.

## Scope

- Production app: `/Applications/cmux.app`
- Production bundle ID: `com.cmuxterm.app`
- Production workspace snapshot: `~/Library/Application Support/cmux/session-com.cmuxterm.app.json`
- Production preferences: `~/Library/Preferences/com.cmuxterm.app.plist`
- Shared settings: `~/.config/cmux/cmux.json` is already shared and must not be copied.
- Keychain credentials and auth state are intentionally not copied.

## Workflow

Run the bundled deterministic helper from the checkout:

```bash
skills/sync-pull/scripts/cmux-sync pull --tag <tag>
```

The helper discovers and validates the tagged bundle ID, backs up target state, copies only the workspace snapshot, transfers UserDefaults through `defaults` to avoid `cfprefsd` races, and validates the result. It does not quit or launch either app; manage app lifecycle separately.

## Safety

- Do not copy `search.db`, notification history, closed-item history, mobile host identifiers, or keychain data.
- Do not overwrite the production snapshot or preferences during pull.
- Preserve the existing dev files before replacing them.
- Do not quit or launch either cmux app.
- Never use raw `git`, `docker`, or untagged `xcodebuild` commands for this workflow.
