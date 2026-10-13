---
name: pardex-online
description: Edit PARDEX WebSocket protocol, sessions, chat, rooms, friends, identity, recovery or launcher/server handoff.
---

- Trace only the changed packet/state across its client and server handlers. Use the file map if ownership is unclear; do not read the whole networking stack.
- Preserve reconnect/session recovery, room lifecycle, friendship authorization, one-use recovery and secure game admission.
- Never print raw credentials or live social data. Use temporary local fixtures for tests.
- For protocol changes, update both ends and meaningful regression coverage. Do not invent chat/voice/store capabilities or break older clients unintentionally.
- A client edit does not authorize server deployment. Use `pardex-verify` for the relevant checks, not every available workflow.
