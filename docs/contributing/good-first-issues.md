# Good First Issues

This guide is for maintainers and contributors who are preparing approachable
issues in Prism.

Use `good first issue` for tasks that are ready for a contributor who is new to
the project. Use `help wanted` for tasks where outside help is welcome but the
work may need more design context, investigation, or maintainer guidance.

## Good First Issue Checklist

Before adding `good first issue`, make sure the issue has:

- A clear user-facing problem or desired behavior.
- A scope small enough for one pull request.
- Relevant files or modules listed.
- A suggested approach, when there is an obvious one.
- Tests or manual verification steps.
- No requirement for private infrastructure or unpublished release context.
- No required changes to encryption, sync protocol compatibility, account
  recovery, or secret handling unless a maintainer is actively pairing.

Good first issues should be useful enough to review and merge, but not urgent
enough that a maintainer needs to take it immediately.

## Issue Template

````markdown
## Summary

Describe the bug or improvement in one or two sentences.

## Expected behavior

- What should a user be able to do?
- What existing behavior must keep working?

## Relevant code

Likely files:

- `lib/features/...`
- `test/features/...`

## Suggested approach

Describe the likely implementation path. If there are tradeoffs, call them out
so a contributor does not have to infer product behavior.

## Tests

Suggested checks:

```bash
flutter test test/path/to/focused_test.dart
flutter analyze --no-fatal-infos
```

Add manual verification steps for gestures, platform behavior, or visual polish.

## Notes

Mention any non-goals, privacy constraints, or related issues.
````

## Example: Board Post Text Selection

Title:

```text
Make board post text selectable for copying
```

Labels:

```text
bug, help wanted, good first issue
```

Body:

````markdown
## Summary

Board post text cannot currently be selected or copied from the boards UI.
Users should be able to select and copy board post body text.

## Expected behavior

- Users can select and copy board post body text from board preview tiles.
- Users can select and copy board post body text from the post detail view.
- Existing board interactions still work:
  - tapping non-text areas still opens the post
  - spoilers still reveal normally
  - links and member mentions still work
  - edit/delete actions still work for users with permission

## Relevant code

Likely files:

- `lib/features/boards/widgets/post_tile.dart`
- `lib/features/boards/views/post_detail_screen.dart`
- `lib/shared/widgets/prism_markdown_text.dart`
- `test/features/boards/widgets/post_tile_test.dart`

`PrismMarkdownText` already supports a `selectable` parameter, so this may
mostly be a call-site change.

## Suggested approach

Try passing `selectable: true` to the `PrismMarkdownText` instances that render
board post bodies. Consider whether titles should also be selectable,
especially in the detail view.

Please avoid changing sync, storage, board permissions, or post editing behavior
for this issue.

## Tests

Add or update focused widget tests around board post rendering. At minimum,
verify that board post body markdown is rendered with selection enabled. Manual
verification is also useful because text selection gestures can be
platform-specific.

Suggested checks:

```bash
flutter test test/features/boards/widgets/post_tile_test.dart
flutter analyze --no-fatal-infos
```

## Notes

This should be possible from a normal public clone of `prism-app`; no private
Prism workspace setup should be required.
````
