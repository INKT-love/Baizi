# Baizi Menstrual Care Design

## Goal

Add an optional, private menstrual-care capability to Baizi. A user records
their cycle locally, Baizi predicts their current cycle phase, schedules
discreet local reminders, and gives the model a minimal phase-aware context
when the user chooses to enable it for a conversation.

This is a wellbeing aid, not a medical, fertility, or contraceptive tool.
It must not diagnose conditions or present predictions as medically certain.

## User Experience

The Advanced Features area in Settings gains a Menstrual Care entry. The
first-use flow asks only for the most recent period start date, average cycle
length (28 days by default), and usual period length (5 days by default).

The care page shows the estimated current phase, the next expected start date,
and a compact period history. The user can record that a period started or
ended today, correct any date, delete an individual record, or clear the
feature's complete local dataset. Recording a start date recalculates future
predictions immediately.

The feature is globally enabled by default after setup. Each conversation has
an independent `Menstrual care context` switch that follows the global setting
until the user turns it off for that conversation. A disabled conversation
never receives cycle information in its model request.

The global settings include:

- Menstrual care context
- Local menstrual reminders
- Reminder time and advance-reminder days
- Automatically recognize and record explicit start/end statements

## Cycle Calculation

The local cycle engine uses a period start date as its anchor. It prefers the
average duration of recent completed recorded cycles when sufficient records
exist; otherwise it uses the configured average cycle length. The result is a
best-effort state: period, post-period, ovulation-window vicinity, pre-period,
expected-start day, or delayed/irregular.

An explicit user record always wins over a prediction. A cycle is considered
noticeably irregular when its actual duration differs from the user's expected
duration by seven or more days. The UI and model context then describe the
state as an estimate and encourage continued tracking. Repeated major changes,
unusually severe pain, or unusual bleeding should be met with a suggestion to
consult a healthcare professional rather than a diagnosis.

Ovulation estimates are labelled as approximate and are never presented as
contraception guidance.

## Model Context And Care Behaviour

Before a model request, Baizi builds a small hidden context only when the
feature is enabled globally and for that conversation. It contains the current
phase and relevant prediction window, not the full cycle history or exact
historical dates. Example meaning: the user may be on day two of their period,
so retain the current assistant or character persona and be considerate when
the topic makes that useful.

The instruction explicitly requires the model to preserve the active character
card, assistant prompt, and conversational tone. It should not interrupt an
unrelated conversation with a menstrual-care message. When the user discusses
fatigue, pain, rest, food, exercise, alcohol, or other potentially relevant
topics, it may respond with concise, empathetic, non-diagnostic care.

The instruction must avoid unsupported absolute rules. For example, it may say
that a user who feels unwell after cold or spicy food could choose warm, mild
food, but it must not state that such food is universally forbidden during a
period. The model must not claim to be a doctor, diagnose, or provide a
guaranteed treatment.

When a period is expected to end or has just ended, the context permits a
natural check-in if relevant. It does not require a forced message.

## Automatic Recording

Automatic recording is fully local and uses deterministic detection on the
user's outgoing messages. It recognizes only explicit first-person assertions
such as that the user's period began today or ended today. Model messages,
quoted material, pasted character-card content, and roleplay text do not
participate.

On a successful recognition, Baizi writes the record and shows an immediate
undo affordance. The user can disable automatic recognition at any time. The
detector does not use an LLM, send messages to a service, or infer dates from
ambiguous wording.

## Reminders

Android uses scheduled local notifications so reminders can occur while Baizi
is closed. The schedules are rebuilt whenever the profile or records change,
and cancelled when reminders or the feature are disabled. Notifications cover
an advance reminder, the expected start day, the expected end day, and a
delayed-cycle check-in. Their default text is intentionally discreet and does
not expose menstrual details on the lock screen.

Baizi requests notification permission only when the user enables reminders.
Device restart and application launch restore valid future schedules. Desktop
builds expose the profile and model context but do not create scheduled system
notifications in this release. Background model calls are explicitly out of
scope: proactive care means a local notification, not an unrequested API call
or a fabricated assistant message.

## Data And Privacy

The feature uses its own encrypted local data store. Its encryption key lives
in platform secure storage. The store contains the profile, cycle records,
reminder options, and per-conversation context exclusions; no cycle data is
stored in chat messages.

Menstrual-care data is excluded by default from general chat backup, export,
character-card import/export, logs, and diagnostics. A later dedicated export
or import path must be explicitly chosen by the user and encrypted. Clearing
the feature removes the dedicated data and all schedules after confirmation.

Only the minimal calculated phase context crosses the selected model API
boundary. Exact dates and history remain on the device.

## Architecture

`MenstrualCareProfile` and `MenstrualCycleRecord` represent local data.
`MenstrualCareStore` handles encrypted persistence and secure-key lifecycle.
`MenstrualCareProvider` owns profile state, phase calculation, mutation,
automatic-recording eligibility, and listener updates. A pure cycle-calculator
module makes date prediction independently testable.

`MenstrualReminderScheduler` is the only component that talks to local
notification APIs. It owns Android channel setup, permission checks,
scheduling, cancellation, and schedule restoration.

`MenstrualCarePromptContext` produces the minimal hidden instruction consumed
by the existing prompt transformer. A per-chat preference store determines
whether that instruction is included. The outgoing-message path invokes the
deterministic recognizer before assembling the model request, and exposes a
reversible UI result.

## Failure Handling And Tests

No notification permission, unavailable secure storage, invalid stored dates,
or a scheduling failure must leave chat usable and show a clear recoverable
state in Settings. A disabled profile produces no model context, writes, or
notifications. Invalid input dates and impossible durations are rejected
locally.

Tests cover phase calculation, recent-cycle averaging, delay and irregularity
thresholds, exact-date redaction from prompt context, per-chat exclusion,
recognizer false-positive guards, undo behaviour, notification schedule
generation/cancellation, and disabled-feature behaviour.
