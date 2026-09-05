# Task 064 — Upstream Workspace Integration

Status: In Progress

## Outcome

Integrate upstream RelayBar 1.5.1's Remote Files workspace and group controls
without losing Scion's browsing or SSH safety behavior.

## Delivery Boundary

Include the split workspace, recent locations, single-file uploads, visible
group controls, and upload-safety hardening. Keep Scion's identity, version,
update feed, and release machinery unchanged. No release is authorized.

## Work

- Preserve symbolic-link browsing, initial-open cancellation, direct-file Back,
  SSH config Includes, strict SFTP decoding, private downloads, accessibility,
  and network-change reconnection.
- Bound both upload-cleanup paths inside the SFTP service; cancel and reap the
  actual child before completing retirement.
- Distinguish unattempted, uncertain, and confirmed publication. A lost reply
  cannot prove that no file was published, nor can target existence prove who
  published it.
- Open local upload sources without following symlinks, validate the descriptor,
  and copy through bounded buffers into private temporary storage before SSH.
- Update system specs and record verification without borrowing upstream's
  completion claims.

## Acceptance

- Regression tests fail before each upload fix and pass afterward in macOS CI.
- Warnings-as-errors package tests, unsigned Xcode Release build, task registry,
  and `git diff --check` pass on the reviewed head.
- Hung cleanup receives TERM/KILL and is reaped; publication uncertainty stays
  visible; swapping the chosen path cannot change the uploaded source.
- Real-server open, revisit, preview, download, upload, replace, cancel, retry,
  history removal, window close, and Quit are verified on an isolated writable
  target, including unsupported publication extensions.
- Aqua/Dark Aqua, minimum width, keyboard focus, VoiceOver, and replacement
  confirmation are reviewed on the integrated build.

## Pending Evidence

Local review runs on Linux without Swift or AppKit. macOS CI covers automated
checks; it skips opt-in live-SSH and visual tests. Upstream's Task 037 also
records live-SSH verification as pending. Neither source substitutes for live
or visual acceptance of this integration. Keep this task active until that
remaining evidence is recorded.
