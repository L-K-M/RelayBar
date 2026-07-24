# Task 004 — Group Saved Forwards by Tag

Status: Complete

Created: 2026-07-24

Completed: 2026-07-24

## Outcome

Add one optional group tag to each saved forwarding item and use it to organize the menu-bar list into quiet sections. Each item appears once. Existing rows, controls, and status behavior stay unchanged.

The tag belongs to the saved profile root, currently `Tunnel`, rather than an individual forwarding rule. [Task 003](003-flexible-ssh-forwarding.md) must preserve the field through its model migration, regardless of implementation order.

## Delivery Boundary

### Included

- One optional, user-written group tag per saved forwarding item.
- One native **Group · Optional** picker in the existing editor.
- A **Move to Group** submenu inside the existing row menu.
- Automatic section grouping when at least one item has a group.
- Lightweight **Rename Group…** and **Ungroup All** section actions.
- Stable normalization, ordering, persistence, migration, validation, and tests.
- Light and dark appearance, keyboard use, narrow-window layout, and long-label checks.
- System documentation and verification evidence.

### Excluded

- Multiple tags on one item.
- Tag colors, icons, chips, nested tags, smart tags, and rules that assign tags automatically.
- Search, filtering, a separate tag manager, a second navigation mode, or a settings screen.
- Persisted empty groups or a second group model separate from item tags.
- Collapsible sections, drag-and-drop between sections, and group-level start or stop actions.
- Grouping the Remote Files server picker.
- Deployment or publication.

## User Experience

```text
RelayBar                         +

Work                            ···
  Hermes Dashboard          ··· ▶
  Virtual Desktop           ··· ▶

Personal                        ···
  Photos                    ··· ▶

Ungrouped
  Scratch                   ··· ▶

Remote Files…
```

- Place **Group · Optional** directly below **Name** in the existing editor.
- Offer **Ungrouped**, each existing group, and **New Group…**. Choosing **New Group…** replaces the picker with one inline name field; Return creates and selects the group.
- Add the same choices under **Move to Group** in the row's existing `···` menu so reassignment does not require opening the full editor.
- Keep the current flat list while every item is ungrouped. As soon as one item has a group, show named sections and an **Ungrouped** section when needed.
- Render each section name as one small secondary system label. A trailing `···` menu appears when the header is hovered or keyboard-focused and is also available from the header's context menu.
- Limit the section menu to **Rename Group…** and **Ungroup All**. Empty groups disappear because groups are derived from item tags.
- Do not add a count, icon, color, background, disclosure control, or tag chip.
- Sort named sections with localized standard ordering. Put **Ungrouped** last. Preserve saved-item order inside each section.
- Keep the tunnel row unchanged. The section heading carries the tag, so the row does not repeat it.
- Changing only a tag moves the row without stopping or restarting its SSH process.

## Work

### 1. Add bounded tag metadata

- Add an optional tag to the saved root model and decode older records without a tag as untagged.
- Derive the set of groups from assigned item tags. Do not persist a separate group collection or allow an empty group.
- Trim leading and trailing whitespace, collapse internal whitespace runs, and limit the result to 32 user-visible characters.
- Reject line breaks, control characters, and an over-limit value beside the field before save.
- Match existing tags by a locale-independent, case-insensitive canonical key. Reuse the existing saved spelling when `work` matches `Work`.
- Rename a group by updating every matching item tag as one metadata operation. **Ungroup All** clears every matching tag.
- Keep canonicalization and grouping in small model helpers outside SwiftUI row bodies.
- Preserve the tag when Task 003 migrates a tunnel to a forwarding profile, regardless of implementation order.

### 2. Add one reusable group control

- Use one compact picker in create and edit flows without a new editor section or modal.
- Reuse its group choices in the row's existing menu instead of adding a permanent row control.
- Reveal one inline text field only while naming or renaming a group.
- Preserve the selected group when Quick Add fills connection fields.
- Keep the existing save, cancel, focus order, validation layout, and editor height behavior.
- Support Tab, arrow keys, Return, and Escape through the picker and inline name field.
- Do not add token controls, a management window, or onboarding text.

### 3. Group the list without changing rows

- Build buckets in one pass over saved items, then sort only the distinct named tag keys.
- Treat untagged items as one bucket.
- Use the existing flat `LazyVStack` when every item is ungrouped.
- Once any tag exists, add section labels and reuse the current row unchanged below each label.
- Keep section actions in the header menu. The heading itself does not collapse, select, start, or stop a group.
- Ensure every item identity appears exactly once and all row actions still target the correct item.
- Keep Remote Files server deduplication based only on SSH connection identity. Tags must not split or merge server choices.

### 4. Preserve process state

- Treat a tag-only save as metadata. Do not stop, restart, retry, or replace the managed SSH process.
- Apply move, rename, and ungroup operations as metadata-only changes.
- Keep the current phase, pending browser action, retry state, and process ownership attached to the stable item UUID while its row moves.
- Continue using the normal stop-and-replace path when connection or forwarding fields change.

### 5. Document and verify

- Add focused tests for legacy decoding, validation, canonical matching, section ordering, the flat-list threshold, ungrouped placement, move, rename, ungroup-all, stable row identity, and tag-only edits on active items.
- Review zero-tag, one-bucket, mixed-tag, all-tagged, all-untagged, long-tag, and many-section fixtures at the 380 × 440 popover size in light and dark appearance.
- Update current system specs only when the behavior is implemented.
- Record implementation evidence in `docs/verification/004-group-saved-forwards-by-tag.md`.

## Acceptance

- Existing saved items decode as untagged and render in the same flat list as before.
- The editor adds one optional group picker and no new section, modal, or permanent row control.
- The picker and **Move to Group** submenu offer **Ungrouped**, existing groups, and **New Group…** in the same order.
- Creating or renaming a group uses one inline name field with clear Return, Escape, validation, and focus behavior.
- `Work`, `work`, and values with harmless surrounding whitespace resolve to one `Work` section when that spelling already exists.
- Empty tags share one **Ungrouped** bucket; invalid and over-limit tags cannot be saved.
- An all-ungrouped list stays flat. Assigning the first group adds named sections in localized order and **Ungrouped** last when needed.
- **Rename Group…** changes every item in that group without creating a duplicate section. **Ungroup All** moves every item to **Ungrouped**, and the empty group disappears.
- Each saved item renders once, keeps its current row layout, and retains working open, edit, delete, start, and stop actions.
- Moving, renaming, or ungrouping a starting, running, retrying, stopped, or failed item preserves that phase and does not launch or terminate a process.
- Editing connection or forwarding data retains the existing stop-and-replace behavior.
- Long valid tags truncate cleanly at the current popover width without covering a row or action.
- The implementation adds no dependency, asset bundle, index, cache, search path, empty-group record, or second persisted grouping model.
- Section derivation uses `O(n + g log g)` time and `O(n + g)` storage for `n` saved items and `g` distinct tags, and is covered independently from SwiftUI rendering.
- Task 003 migration preserves tags on the profile root, and individual forwarding rules never own grouping tags.
- Remote Files presents the same deduplicated server choices before and after tags are assigned.
- Focused tests, `swift test`, the warnings-as-errors app build, `plutil -lint`, and `git diff --check` pass.
- Current system specs and `docs/verification/004-group-saved-forwards-by-tag.md` describe the implemented behavior and recorded visual checks.
- No release, notarization, publication, or deployment occurs without separate explicit approval.

## Completion Artifacts

- Optional tag model, normalization, and grouping helper
- Editor field and grouped list presentation
- Focused model, store, and UI tests
- Updated system specs and verification report

Completion evidence is recorded in [Task 004 verification](../../verification/004-group-saved-forwards-by-tag.md).
