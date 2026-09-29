# Task 066 — Resizable Menu Popover

Status: In Progress

Created: 2026-09-29

## Outcome

The menu opens larger by default, and you can drag it larger or smaller.
It reopens at the size you chose.

## Delivery Boundary

- The default content size grows from 380 × 440 to 420 × 580 points.
  380 × 440 becomes the minimum, so no drag reaches an unverified layout.
- A grip in the bottom-trailing corner resizes the popover on every
  screen: list, editor, and Settings. The grip's accessibility element is
  adjustable, so VoiceOver can grow or shrink the menu in fixed steps.
- The size is clamped to at most 720 points wide and to the visible frame
  of the screen the menu opens on, less a 40-point margin. Opening on a
  smaller screen clamps without overwriting the stored preference.
- The popover keeps its transient behavior, anchor, and arrow. It does not
  become a detachable or free-floating window.

## Work

- Add `PopoverSizeLimits` (pure clamp and drag math) and
  `PopoverSizeModel` (stored preference and effective size) in
  `PopoverSizing.swift`, with the `PopoverResizeGrip` view.
- Make the popover's content size the single size authority: the root
  view fills its host and `NSHostingController.sizingOptions` is empty.
- Update the application-shell and data-and-state specs and the interface
  principles' content budget.
- Add unit tests for limits, drag math, persistence, and screen clamping.

## Acceptance

- A fresh install opens the menu at 420 × 580 points.
- Dragging the grip down and outward enlarges the menu with the corner
  following the pointer while the menu is centered on its icon, and the
  size never passes the minimum, the 720-point width, or the screen.
- Closing and reopening the menu, and relaunching RelayBar, keeps the
  chosen size.
- VoiceOver increment and decrement on **Resize menu** change the size.
- The grip does not intercept clicks on **Quit**, **Save**, or **Cancel**.
- `swift test -Xswiftc -warnings-as-errors`, the Release build, and
  `git diff --check` pass.
- Manual: the list, editor, and Settings screens show no clipping or
  horizontal movement at the minimum, default, and a maximum size, in light
  and dark appearance.
