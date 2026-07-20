# Baizi Menstrual Care Implementation Plan

- Date: 2026-07-20
- Specification: `docs/superpowers/specs/2026-07-20-baizi-menstrual-care-design.md`
- Baseline: `422632d`

## Acceptance

- A user can configure, correct, clear, and privately inspect their cycle.
- Only eligible conversations receive a minimal calculated context, never raw
  history or exact dates.
- Explicit user start/end messages can create reversible local records.
- Android reminders survive process restarts without background LLM requests.
- General backup/export and logs omit menstrual-care data.
- Localized UI, formatter, analyzer, focused tests, and Android split release
  build succeed.

## Phase 1: Domain And Encrypted Storage

1. Add immutable profile, record, phase, and recognition-result models.
2. Add a pure calculator for date normalization, historic-average selection,
   phase prediction, expected dates, and irregularity detection.
3. Add a dedicated secure-storage-backed encryption-key service and encrypted
   Hive store. Keep it independent from chat backup stores.
4. Add `MenstrualCareProvider` for loading, validation, profile updates,
   records, per-chat exclusions, and undoable mutations.
5. Write unit tests for calculations, persistence migrations, invalid input,
   redaction, and record edits.

## Phase 2: Prompt Context And Message Detection

1. Add a context builder that accepts only a calculated phase and creates a
   concise, non-diagnostic instruction preserving persona and character-card
   behaviour.
2. Add deterministic first-person Chinese start/end pattern recognition with
   conservative exclusions for quoted/roleplay-style text.
3. Integrate the context builder at the existing `MessageBuilderService`
   system-prompt boundary.
4. Integrate recognizer invocation in `ChatActions` before request assembly;
   expose its mutation result to the UI so it can be undone.
5. Add chat-scoped context preference storage and resolve global/default/
   disabled states for each conversation.
6. Test context omission, exact-date non-disclosure, disabled chats, explicit
   recognition, false-positive guards, and undo behaviour.

## Phase 3: Local Reminders

1. Extend notification initialization with a dedicated private menstrual-care
   channel and Android scheduling support.
2. Introduce a scheduler that calculates start, end, advance, and delayed
   reminders, cancels stale schedules, and restores future schedules at app
   startup.
3. Request notification permission only when reminder settings are enabled;
   render a recoverable denied-permission state.
4. Verify scheduling calculations with tests and smoke-test Android runtime
   permission and notification delivery.

## Phase 4: Settings And Conversation UI

1. Add the Advanced Features entry and first-use configuration flow.
2. Add the care page: status card, record history, manual start/end logging,
   edit/delete/clear controls, reminder controls, and privacy explanation.
3. Add the per-chat context control to the existing conversation menu.
4. Show an unobtrusive undo snackbar after automatic recording; do not render
   private cycle status in ordinary chat UI.
5. Add translations to every existing ARB locale and regenerate localization
   output.
6. Add focused widget tests for setup, validation, toggle behaviour, undo, and
   the per-chat override.

## Phase 5: Integration Validation And Delivery

1. Confirm backup/export paths and diagnostics exclude the new storage.
2. Run `flutter pub get`, code generation if Hive adapters are used, `dart
   format`, `flutter analyze`, and focused/full test suites.
3. Build Android `armv8a` and `armv7a` release APKs with R8/resource shrinking.
4. Verify APK version, ABIs, and signing; manually test setup, scheduled
   reminder, chat context, character persona preservation, automatic recording,
   undo, and disable paths on Android.
5. Update the release notes with the actual feature scope and publish the two
   ABI assets to both GitHub and OpenList only after validation.

## Guardrails

- No LLM call, network request, or assistant chat message may be initiated by
  a reminder or automatic recorder.
- No medical diagnosis, treatment claim, or contraceptive guidance is added.
- Never include exact cycle dates or historical records in model prompts.
- Never stage `update_192_168_5_55.py`.
- Do not create scheduled desktop reminders in the initial release.
