---
name: sync-push
description: "Synchronize cmux workspaces and preferences from the current tagged local dev build into the production /Applications/cmux.app installation, then relaunch production cmux. Use when the user asks to push or sync cmux state to production."
---

# Sync Push

Export the current tagged local dev cmux state into the production installation.

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
skills/sync-pull/scripts/cmux-sync push --tag <tag>
```

The helper discovers and validates the tagged bundle ID, backs up the production state, copies only the workspace snapshot, transfers UserDefaults through `defaults` to avoid `cfprefsd` races, and validates the result. It does not quit or launch either app; manage app lifecycle separately.

## Safety

- This is a destructive replacement of the production workspace snapshot and preferences; always make the backups first.
- Do not quit or launch either cmux app.
- Do not copy `search.db`, notification history, closed-item history, mobile host identifiers, or keychain data.
- Do not rebuild or modify the dev app during push.
- Never use raw `git`, `docker`, or untagged `xcodebuild` commands for this workflow.
