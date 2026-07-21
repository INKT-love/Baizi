# Chat Appearance Implementation Plan

1. Add appearance data types and a `ChatAppearanceProvider`.
   - Persist the background mode and exact-model-ID profile map separately from
     provider model overrides.
   - Keep model IDs final and expose read-only lookup/update APIs.
   - Reuse the managed avatar/image directories and safe replacement cleanup.

2. Register the provider and add display resolution helpers.
   - Register it in the application provider tree.
   - Resolve user identity from `UserProvider` and assistant identity from each
     message's stored model ID.
   - Resolve the active background from either the selected model or the latest
     assistant message, with safe fallbacks for legacy messages.

3. Update chat rendering.
   - Use the resolver in `ChatMessageWidget` so old messages redraw immediately
     when a model profile changes.
   - Replace the current assistant-only background selection in mobile, tablet,
     and desktop chat layouts with the selected model profile background.
   - Preserve existing assistant character-card presentation when no model
     appearance is configured.

4. Add the settings and editor flow.
   - Build a Chat Appearance page for user identity, background mode, and model
     profile list.
   - Add an editor with a read-only model ID, nickname field, avatar picker,
     background picker, crop flow, clear actions, and restore-default action.
   - Add a deep-link row from the existing model detail sheet.

5. Integrate backup and tests.
   - Include the appearance store and managed assets in backup/restore.
   - Add unit and widget coverage for persistence, immutable IDs, rendering,
     background modes, and API isolation.
   - Run focused tests, formatting, static analysis, and a release build before
     publishing.
