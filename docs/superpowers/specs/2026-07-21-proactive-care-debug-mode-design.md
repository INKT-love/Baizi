# Proactive Care Debug Mode

## Goal

Make the proactive care screen report why a request was not sent, and provide
a deliberate test mode for checking a model request more than once on the same
day without weakening the normal daily protection.

## Behaviour

- The normal foreground timer and Android WorkManager continue to send at most
  one successful proactive care message per period day.
- A new persisted `debugModeEnabled` setting appears only with the proactive
  care controls. Its description makes clear that it affects manual testing,
  may consume API quota, and never changes automatic scheduling.
- When debug mode is enabled, the manual "send now" action bypasses only the
  same-day success check. It still requires a configured, currently open
  period record and still validates model, network, and destination.
- The proactive decision carries an explicit blocked reason: disabled,
  no active period, already sent today, or not yet at the scheduled time.
  The settings page maps each reason to a precise Chinese status message.

## Data and Compatibility

`debugModeEnabled` defaults to `false` when absent from existing local secure
storage, so existing users keep the normal once-daily behaviour.

## Verification

- Unit tests cover each decision reason and confirm that debug mode bypasses
  only the same-day success check.
- Analyse and run the focused menstrual-care test suite.
- Install the signed arm64 APK on the connected device and verify the page
  shows the correct "already sent today" state; enable debug mode and verify a
  manual request is allowed.
