# Baizi Proactive Menstrual Care Implementation Plan

- Date: 2026-07-20
- Specification: `docs/superpowers/specs/2026-07-20-baizi-proactive-menstrual-care-design.md`
- Baseline: `ea0918e`

## Acceptance

- Android sends one model-generated care reply per active-period day at the
  configured time, with a startup catch-up when it missed its schedule.
- The expected end day asks whether the period has ended.
- The user chooses recent-chat or dedicated-chat delivery, network policy, and
  time; the default destination is the most recent chat.
- No task repeats a same-day request after success or failure.
- Normal chat, consent boundaries, and local menstrual records remain intact.

## Phase 1: Persistence And Eligibility

1. Extend the secure profile with active-care settings and daily run state.
2. Add pure eligibility, destination, and end-day prompt-selection helpers.
3. Cover cycle boundary, once-per-day, catch-up, disabled, and end-record
   cancellation with unit tests.

## Phase 2: Background Scheduling

1. Add a maintained Android WorkManager dependency and manifest requirements.
2. Register unique delayed work for the configured time and constrained network.
3. Re-register/cancel on profile changes and evaluate a startup catch-up.
4. Initialize plugin registration safely in the headless worker.

## Phase 3: Proactive Request Service

1. Resolve the selected model, credential, assistant persona, and destination.
2. Build a bounded, tool-free proactive prompt using authorized cycle data.
3. Stream/collect the response through the existing Baizi API path and persist
   it as one normal assistant message.
4. Persist result state before returning so the worker cannot duplicate a run.

## Phase 4: Settings And Validation

1. Add active-care controls, destination selector, time picker, network policy,
   status, and explicit cost/privacy notice to Menstrual Care settings.
2. Run focused tests, formatter, analyzer, and Android scheduled-work smoke
   validation.
3. Build, sign, and publish split Android packages only after verification.
