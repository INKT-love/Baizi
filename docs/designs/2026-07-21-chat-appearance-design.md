# Chat Appearance Profiles

## Goal

Let a user personalize their own chat identity and give every model an
independent display nickname, avatar, and chat background. The model ID stays
immutable and remains the sole value used for API requests.

## Confirmed Behavior

- The user has one global nickname and avatar.
- Each exact model ID has an independent nickname, avatar, and background.
- Changing a profile immediately updates all rendered history. Assistant
  messages resolve their profile from the message's stored model ID.
- Background behavior is user-selectable:
  - Follow the currently selected model.
  - Follow the most recent assistant reply in the open conversation.
- Avatars and backgrounds come from the photo library, support cropping, and
  can be cleared or restored to the default appearance.

## Data Model

Add a separate persisted chat-appearance store rather than extending
`ProviderConfig.modelOverrides`. It contains:

- A background behavior enum.
- A map from an exact, immutable model ID to a model appearance profile.
- Each profile has an optional display nickname, avatar path, and background
  path.

The existing `UserProvider` remains the owner of the global user nickname and
avatar. The appearance store does not include API model IDs, API model aliases,
provider protocol options, or any request headers.

## UI

Add a `Chat Appearance` settings page with three areas:

1. User identity: edit nickname and avatar.
2. Background behavior: a two-option selector for the two confirmed rules.
3. Model appearances: a searchable model list; each row shows the effective
   model avatar and nickname, and opens an editor. The immutable model ID is
   shown as read-only supporting text.

The existing long-press model detail sheet includes a `Chat appearance` row
that opens the same editor for that model. This provides a direct route from
model selection without exposing model-ID editing.

## Rendering Rules

- User messages use the global user nickname and avatar at render time.
- Assistant messages use the profile for their stored model ID at render time.
  Messages without a model ID fall back to the effective current model.
- In current-model mode, the open chat's background uses the effective selected
  model. In latest-reply mode, it uses the model ID on the latest assistant
  message, falling back to the effective selected model.
- A profile update notifies the chat UI, so existing messages redraw without
  rewriting Hive conversation or message data.

## Asset Storage And Migration

Selected images are cropped first and copied into the managed avatars or images
directory. Replaced managed files are removed only after a successful copy;
external files are never deleted. Old installs with no appearance store use
the current user profile and default model appearance without migration prompts.
The store participates in normal settings backup and restore.

## Validation

- Unit tests cover profile persistence, immutable model IDs, image ownership,
  rendering resolution for historical messages, and both background modes.
- Widget tests cover the settings page, model editor, reset actions, and
  immediate UI refresh.
- API request tests confirm cosmetic profile fields never alter model IDs or
  outbound request payloads.
