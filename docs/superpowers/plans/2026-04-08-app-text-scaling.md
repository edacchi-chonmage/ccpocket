# App Text Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make app text readable by combining OS text scaling with an app-level five-step text size setting, then fix the smallest chat/settings UI text that still ignores the scale.

**Architecture:** Persist a text-scale preset in `SettingsCubit`, expose its multiplier via `SettingsState`, and apply it at the `MaterialApp.router` boundary by overriding `MediaQuery.textScaler`. Raise the base `TextTheme` slightly, then replace the worst fixed `fontSize` values in chat/settings surfaces with theme-based styles or scaled values.

**Tech Stack:** Flutter, flutter_bloc, shared_preferences, widget tests

---

### Task 1: Settings model and persistence

**Files:**
- Modify: `apps/mobile/lib/features/settings/state/settings_state.dart`
- Modify: `apps/mobile/lib/features/settings/state/settings_cubit.dart`
- Test: `apps/mobile/test/settings_cubit_push_test.dart`

- [ ] Add a failing test that loads and updates the new text-scale preset.
- [ ] Run the focused settings cubit test and confirm it fails for the missing setting.
- [ ] Add the preset enum/value object plus persistence in `SettingsCubit`.
- [ ] Re-run the focused settings cubit test and confirm it passes.

### Task 2: App-wide text scaling

**Files:**
- Modify: `apps/mobile/lib/main.dart`
- Modify: `apps/mobile/lib/theme/app_theme.dart`
- Test: `apps/mobile/test/widget_test.dart`

- [ ] Add a failing widget test proving app-level text scale composes with OS scale.
- [ ] Run the focused widget test and confirm it fails before implementation.
- [ ] Override `MediaQuery.textScaler` in `CcpocketApp` and raise the base text theme slightly.
- [ ] Re-run the focused widget test and confirm it passes.

### Task 3: Priority UI fixes for chat/settings readability

**Files:**
- Modify: `apps/mobile/lib/features/settings/settings_screen.dart`
- Modify: `apps/mobile/lib/widgets/message_bubble.dart`
- Modify: `apps/mobile/lib/widgets/bubbles/assistant_bubble.dart`
- Modify: `apps/mobile/lib/widgets/bubbles/streaming_bubble.dart`
- Modify: `apps/mobile/lib/widgets/bubbles/permission_request_bubble.dart`
- Modify: `apps/mobile/lib/widgets/bubbles/ask_user_question_widget.dart`
- Modify: `apps/mobile/lib/widgets/chat_input_bar.dart`
- Test: `apps/mobile/test/chat_input_bar_test.dart`

- [ ] Add a failing widget test for the visible text-size control in settings and/or input readability expectations.
- [ ] Run the focused widget test and confirm it fails for current tiny fixed text.
- [ ] Replace the smallest fixed text styles with theme-based or scaled styles in the priority surfaces.
- [ ] Re-run the focused widget test and confirm it passes.

### Task 4: Verification

**Files:**
- Modify: none
- Test: `apps/mobile/test/settings_cubit_push_test.dart`
- Test: `apps/mobile/test/widget_test.dart`
- Test: `apps/mobile/test/chat_input_bar_test.dart`

- [ ] Run the targeted widget tests covering settings, app shell, and chat input.
- [ ] Run `dart analyze apps/mobile`.
- [ ] Run `cd apps/mobile && flutter test`.
