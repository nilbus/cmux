---
name: rebuild
description: "Build and install the latest cmux code for this checkout on the user's devices. Use when the user asks to rebuild, refresh, or install cmux on their iPhone and Mac; launches iOS by default, but does not launch macOS without explicit permission."
---

# Rebuild

Build and install the latest cmux code for the user's devices.

## Defaults

- Always use the current tagged workflow. Do not use untagged builds.
- iOS target is the physical iPhone, not the simulator.
- Build/install the iOS app and launch it on the phone.
- Build/install the macOS app, but do **not** launch or relaunch it without explicit permission because it may be running active sessions.

## Workflow

Use the repository scripts rather than inventing a new build path:

```bash
./scripts/reload.sh --tag <tag>
ios/scripts/reload.sh --tag <tag> --device-only
```

For iOS, the device leg must pass the authenticated/paired auth gate. If the gate times out after install, rerun the supported verification path before deciding the build failed:

```bash
scripts/verify-iphone-auth.sh --tag <tag> --device-id <device-id>
```

## Safety

- Never use raw `git`, `docker`, or untagged `xcodebuild` commands for this workflow.
- Do not quit or relaunch the macOS app unless the user explicitly asks.
- Do not bypass iOS auth/sign-in requirements.
- If the iPhone is offline or locked, leave the queued/retriable state intact and report the exact retry command.
