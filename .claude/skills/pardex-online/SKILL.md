---
name: pardex-online
description: Use for PARDEX WebSocket sessions, rooms, friends, presence, invitations, identity, account recovery, notifications, secure handoff, server or Railway-facing backend code.
version: 1.0.0
effort: medium
---

# PARDEX Online

Start from the exact client/server concern; do not read the entire networking stack.

## File routing

- Client protocol/state: `scripts/online/pardex_online.gd`
- Secure handoff: `scripts/online/pardex_online_secure_handoff.gd`
- Identity validation: `scripts/online/pardex_identity_guard.gd`
- Launch handoff: `scripts/online/pardex_game_launcher.gd`
- Notifications: `scripts/online/pardex_notifications.gd`
- Server core: `server/server_core.js`
- Social persistence: `server/social_store.js`
- Entry/deploy: `server/server.js`, `server/production_server.js`, `server/DEPLOYMENT.md`

## Safety / compatibility

- Preserve session recovery and existing room/social protocol behavior unless explicitly changing it.
- Never expose raw identity keys, recovery codes, secrets or `server/data`.
- Do not invent server support for chat/voice/store/account features.
- For protocol changes, update client + server + focused smoke coverage together.
- Keep backward-compatible packet handling where practical.

## Verification

For server/protocol changes run:

```bash
cd server && npm test
```

For a very local server change, run the specific smoke test first; run the full suite before declaring a protocol change complete.

Do not trigger Railway deployment merely for client-only changes.
