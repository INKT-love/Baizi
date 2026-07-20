# Baizi Proactive Menstrual Care Design

## Goal

Extend Baizi's menstrual-care feature so Android can proactively request the
currently selected model once per day during a recorded period, then save only
the generated assistant reply in a selected conversation. The expected end day
uses a considerate question asking whether the period has ended.

This feature is optional, defaults to disabled, and is a wellbeing aid rather
than medical advice, diagnosis, or contraceptive guidance.

## User Experience

Menstrual Care gains an `Active menstrual care` section with:

- A master enable switch, off by default
- A daily care time
- Destination selection: `Most recent conversation` by default or a dedicated
  `Menstrual care` conversation
- An `Allow mobile data` switch
- A last-run status and a one-time error status

When enabled, Baizi proactively writes one assistant message daily on each day
of the active period. The most recent conversation is resolved when the task
runs, not when the user saves settings. A dedicated destination is created on
first use if selected, then reused for later care messages.

On the estimated final day, the message asks gently whether the user's period
has ended. Explicit first-person user replies such as "我姨妈结束了" continue
to update the local record and prevent later daily care messages for that
period.

## Trigger Rules

The scheduler evaluates only when the profile is configured and active care is
enabled. It sends at most one successful or failed request per local calendar
day during the active recorded period. It does not run before the start date or
after an actual recorded end date.

The task is scheduled at the configured time with Android's background task
mechanism. At application startup and resume, Baizi checks whether today's task
was due but did not run. It performs exactly one catch-up attempt, subject to
the same network and once-per-day rules.

The expected final day uses a distinct end-check instruction. If the user has
not recorded an end date, the task remains eligible for later days, but does
not diagnose an irregularity or force a conclusion.

The current conversation destination may be unavailable after deletion or
temporary-chat use. In that case, the task records a recoverable failure and
does not create a message elsewhere without the user's chosen destination
policy.

## Model Request And Reply

The background request uses the user's currently selected Baizi model and API
key. It receives the same minimal profile context already authorized for normal
chat: latest start/end dates when present, cycle settings, current period day,
and expected end/start dates. It also receives the selected assistant or
character prompt so its tone matches the destination conversation.

The proactive instruction requires one concise, warm message. It varies wording
across period days, does not ask the same question repeatedly, and does not
claim medical authority. On the expected final day it asks whether the period
has ended without presuming that it has. It must not mention internal tools,
hidden records, API requests, or scheduling.

The normal model response is persisted as a regular assistant message in the
destination chat. No synthetic user message, visible system prompt, or hidden
task marker is added to the conversation.

## Privacy, Cost, And Network

Active care makes a real API request and may consume the configured model's
quota. The settings screen states this before enabling. The task runs at most
once daily, has no automatic same-day retries, and cancels remaining schedules
when active care is disabled or the period ends.

The same authorized cycle dates sent in manual-chat care context are sent to the
selected model provider. No full period history, secure-storage contents, or
other conversations are sent. When mobile data is disabled, Android background
work requires an unmetered network; startup catch-up follows the same setting.

## Architecture

`MenstrualCareProfile` gains proactive-care configuration and run-state fields:
enabled state, minutes of day, destination policy, mobile-data allowance, last
attempt date, last successful date, and last error summary. These values remain
in the existing secure menstrual-care store.

`MenstrualCareScheduler` owns Android task registration/cancellation and
startup catch-up evaluation. `MenstrualCareProactiveService` owns pure
eligibility checks, destination resolution, prompt construction, model request,
message persistence, and run-state updates. The background entry point must
initialize only the dependencies needed for this service; it must not render UI
or create a foreground service.

The service reuses the existing Baizi API routing and streaming response parser
where possible, while providing a bounded non-interactive request path for the
background worker. The worker cannot invoke tools, require approval, open UI,
or create a background conversation unless the dedicated destination is chosen.

## Failure Handling And Tests

No model configuration, no API key, unavailable destination, no permitted
network, timeout, invalid response, Android scheduler denial, and app process
termination are recoverable. Each records a concise local status, counts as the
day's one attempt, and leaves normal chat unaffected.

Tests cover daily eligibility, once-per-day state, start/end boundaries,
expected-end prompt selection, catch-up behavior, destination policy, mobile
network constraints, failure non-retry, explicit end-record cancellation, and
prompt safety. Android integration validation covers scheduled execution and
app-start catch-up on a physical device.
