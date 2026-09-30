# Current Product Focus

This is a short-lived direction file for Claude Code. Update it when the product direction changes; do not copy it into permanent architecture docs.

## Navigation direction

The next launcher navigation target is four primary tabs only:

1. **Mağaza**
2. **Kütüphane**
3. **Arkadaşlar**
4. **Profil**

The older `Ana Sayfa` / `Keşfet` split should not be treated as the final product structure when implementing the next major navigation redesign.

## Visual direction

- Dark futuristic PARDEX shell.
- Cyan / electric-blue accents with restrained glow.
- Rounded premium panels, clean spacing, readable typography.
- Fun and lively, but not cluttered.
- Keep top bar with PARDEX brand, search, notification/reward area, minimize/maximize/close controls.
- Keep responsive desktop behavior: 1366×768 must remain usable; larger screens should use extra space rather than simply scale everything up.
- Prefer editor-visible scene/resources where practical.

## Four page intent

### Mağaza
Featured games, campaigns/discounts, new releases, wishlist/store discovery. Real catalog data should replace placeholder products as games are created.

### Kütüphane
Owned/installed/recent/favorite games, quick launch, updates and continuation state. Do not invent persistent ownership data that does not exist yet; label placeholders clearly.

### Arkadaşlar
Live PARDEX Online data: friends, presence, requests, room invitations, joinable activity. Chat/voice must remain clearly marked as unavailable until backend support exists.

### Profil
Real identity/display name/presence/activity where available. Levels, achievements, badges and playtime must not be presented as real persisted data until implemented.

## Important

Mockup images are design references, not product truth. Do not implement fake backend/account/store data merely because a mockup contains it. Build the UI structure first and connect real data where it already exists.
