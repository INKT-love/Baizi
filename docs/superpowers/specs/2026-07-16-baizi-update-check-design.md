# Baizi Update Check Design

## Goal

Enable Baizi's existing update reminder setting. The app checks for a newer
official Baizi release at startup, exposes the result in the About page, and
offers an optional upgrade prompt from the home screen.

## Update Source

The source is GitHub's latest-release endpoint:

`https://api.github.com/repos/INKT-love/Baizi/releases/latest`

Only stable releases are considered. GitHub pre-releases and drafts are not
offered to ordinary users. The release page, rather than one architecture-
specific APK asset, is opened for upgrades so users can select the APK that
matches their device.

The provider retains support for the existing Baizi manifest shape. It also
recognizes GitHub's release JSON and normalizes it into `UpdateInfo`. This
keeps a later move to self-hosted releases limited to changing the configured
source rather than rewriting the UI or update flow.

## User Experience

The `App update reminders` setting remains the single control and defaults to
enabled. When enabled, the app performs one update check after startup. If a
newer version is found, the home screen displays one dialog during that app
run. The dialog offers `Upgrade now` and `Later`. Choosing upgrade opens the
official GitHub release page in the external browser and states that GitHub
may require a network proxy where it is unavailable.

When reminders are disabled, no automatic check or startup dialog occurs.
Manual checks from About remain available so users can explicitly inspect the
installed version at any time.

The About page always shows an update row. It displays `Checking for updates`,
`Update available`, or `Up to date` as applicable. A network or parsing error
shows a neutral `Unable to check` state and does not block app use. Tapping the
row checks again.

## Architecture

`BaiziBrand` owns the official release API URL. `UpdateProvider` owns fetching,
parsing, version comparison, and status changes. Its parser accepts either the
existing Baizi manifest or GitHub's latest-release response. Version comparison
normalizes a leading `v` and compares major, minor, and patch segments.

The application root starts the check once after settings initialization and
observes the provider result to present the home-level dialog. A run-local guard
prevents repeated dialogs after rebuilds. The mobile and desktop About views
render the same provider state and invoke manual rechecks.

## Failure Handling And Tests

GitHub errors, invalid JSON, malformed versions, and unavailable browsers are
non-fatal. The update provider reports failure without exposing transport
details as user-facing text.

Tests cover GitHub release parsing, leading-`v` semantic comparison, enabled
and disabled startup behavior, one prompt per run, and About-page status text.
