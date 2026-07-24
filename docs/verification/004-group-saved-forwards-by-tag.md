# Task 004 — Group Saved Forwards by Tag Verification

Verified: 2026-07-24

Result: Complete

## Automated evidence

- `swift test` passed 133 tests with 3 opt-in live tests skipped and no failures.
- Model tests cover missing legacy fields, v1 forwarding migration with a tag already present, v2 JSON round trips, whitespace normalization, the 32-user-visible-character bound, line-break and control-character rejection, invalid persisted values, case-insensitive canonical matching, and reuse of existing spelling.
- Grouping tests independently cover the flat all-untagged result, one named bucket, named-section ordering, Ungrouped placement, stable item order, and exactly-once membership.
- Store tests cover move, rename-and-merge, ungroup-all, persistence without a separate group collection, invalid-value rejection, and metadata-only edits in starting, running, retrying, stopped, and failed phases. They also verify that pending browser work and runtime-assigned ports survive tag edits, no SSH invocation is added, and a connection edit still takes the stop-and-replace path.
- Remote Files tests verify that group tags do not change SSH connection deduplication.
- The app target's warnings-as-errors build passed with complete Swift concurrency checking:

  ```sh
  xcodebuild -project RelayBar.xcodeproj -scheme RelayBar \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build
  ```

- `plutil -lint Packaging/Info.plist` and `git diff --check` passed.

## Native UI and accessibility evidence

The DEBUG app ran with `--preview-window --grouping-preview <scenario>` in an isolated `UserDefaults` suite. Light and dark appearances were reviewed at the fixed 380-by-440 menu window size.

- `empty`, `zero-tag`, `all-untagged`, `one-bucket`, `mixed`, `all-tagged`, `long-tag`, and `many-sections` fixtures covered the flat-list threshold, empty state, named-section sorting, Ungrouped placement, scrolling, and the fixed footer.
- Named section headers were quiet secondary labels. Their visually hover/focus-revealed action menus remained keyboard- and accessibility-reachable; Ungrouped intentionally had no group-action menu.
- The row menu's **Move to Group** submenu used **Ungrouped**, sorted existing groups, and **New Group…**, with the current choice checked. The editor used the same order in its **Group · Optional** picker directly below Name.
- **New Group…** and **Rename Group…** used one inline focused field. Return normalized and applied a valid value, Escape canceled it, an over-limit value showed its error beside the field, and Add Profile remained disabled while the new group name was unresolved.
- Quick Add preserved the selected group. Entering `work` reused the saved spelling `Work`; renaming `Work` to `personal` merged the sections without duplicating a group. **Ungroup All** removed the now-empty section and restored the flat list when no named groups remained.
- Row open, menu, start, and stop controls retained their layout and accessibility labels under grouped presentation.
- A maximum-length 32-character wide-label fixture truncated on one line with an ellipsis without covering either row or its action buttons. Accessibility exposed the complete heading and group-action label.
- The many-sections fixture retained localized ordering and scroll behavior in dark appearance.

## Persistence, process, and security review

- `groupTag` is one optional field on the saved profile root. Groups are derived from item tags; no second record, empty-group object, index, cache, dependency, or asset was added.
- Grouping buckets items in one pass, sorts only the distinct named groups, and uses `O(n + g log g)` time with `O(n + g)` storage.
- Tag-only update, move, rename, and ungroup operations retain the stable profile UUID and mutate saved metadata without stopping, launching, retrying, or replacing an SSH process.
- Group names remain local display metadata. They are not passed to SSH, SFTP, a shell, forwarding rules, or Remote Files connection identity.
- A live SSH run was not required for this metadata-only change. The complete fake-process lifecycle suite and the existing forwarding suite passed; the opt-in live tests remained skipped.

No release, notarization, publication, or deployment was performed.
