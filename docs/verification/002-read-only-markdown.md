# Task 002 — Read-only Markdown Verification

Status: Complete

Accepted: 2026-07-24

## Automated evidence

- `swift test`: 106 tests executed, 2 opt-in live tests skipped, and 0 failed.
- `swift test --sanitize=address`: the same 106 tests executed with 2 opt-in live tests skipped, 0 failed, and no Address Sanitizer findings.
- `swift test --sanitize=thread`: the same 106 tests executed with 2 opt-in live tests skipped, 0 failed, and no Thread Sanitizer findings.
- SwiftPM and the Xcode RelayBar target compile with complete strict-concurrency checking; the app target also treats warnings as errors.
- Markdown coverage verifies extensions, BOM handling, GFM parsing, invalid UTF-8, NUL rejection, the 2 MiB cap, external-link policy including percent-decoded control rejection, decoded Unicode relative references, inert relative Markdown references, visible inert alt text for inline/full/collapsed/shortcut Markdown images, omitted Obsidian width and width-by-height hints including table-escaped pipes, same-line and next-line reference destinations, malformed and paragraph-interrupting definition rejection, undefined-reference and ordinary-link preservation, grouped list/block frontmatter values, foldable/nested/built-in/custom Obsidian callouts, custom completed-task markers with indented-code preservation, compatibility syntax inside four-space nested lists, table-safe escaped wiki/embed pipes, two-space multiline footnotes, reading-mode block identifiers, highlights/comments/wiki links/tags/embeds/named and inline footnotes/math, Unicode and nested tag forms, numeric/URL/CSS/code tag non-regressions, aggregate tag lookbehind bounds, multi-line and blockquote/list-nested fenced/indented code-literal preservation, multi-line and link-label raw HTML with allowed-angle-autolink preservation, aggregate enrichment limits with readable overflow, malformed-math source fallback, preview-token rejection of forged private references, internal URL round trips, URL/currency non-regression, non-upscaling math layout, native math bounds, service metadata limits, model state restoration, cancellation propagation and timing-bounded checkpoints inside the real compatibility pass, cancellation during decoding, and temporary cleanup.
- `plutil -lint RelayBar.xcodeproj/project.pbxproj`: passed.
- The Xcode Debug app target builds successfully with complete strict-concurrency checking, warnings as errors, and code signing disabled.
- Debug and Release Xcode builds retain Highlighter's `highlight.min.js`, `github.css`, and `github-dark.css`, plus SwiftMath's selected Latin Modern `.otf`/metrics `.plist` and three font-license files. The measured Release app occupies 6,311,936 bytes (6.0 MiB), down by about 9.7 MiB from the unpruned dependency bundle. Its non-globally stripped executable is 2,258,312 bytes; the executable and generated dSYM share UUID `86920544-7AD1-3F92-8056-F768FDC28512`. Debug remains unstripped.
- Published Markdown state retains the parsed content and private-reference token without additionally storing both the original and compatibility-transformed source strings.
- SwiftPM and Xcode resolve exact versions: MarkdownUI 2.4.1, NetworkImage 6.0.1, swift-cmark 0.8.0 (cmark-gfm), HighlighterSwift 3.1.0, and SwiftMath 1.7.3. A 2026-07-24 upstream audit confirmed the direct pins match their current stable release or tag.
- A 2026-07-24 cross-check against Obsidian's official [basic syntax](https://obsidian.md/help/syntax), [advanced syntax](https://obsidian.md/help/advanced-syntax), [internal links](https://obsidian.md/help/links), [tags](https://obsidian.md/help/tags), and [callout](https://obsidian.md/help/callouts) references confirms the implemented target includes named, two-space multiline, and inline footnotes; comments; custom single-character completed-task markers; nested and Unicode inline tags; both wiki and relative Markdown internal-link formats as inert references; reading-mode block identifiers; table-safe wiki aliases and embed sizes; backtick and tilde fences; indented code; nested fence rules; Markdown content inside callouts; fold markers; nested callouts; built-in aliases; and custom type identifiers.

## Static security evidence

- Markdown is capped before and during transfer, bounded again while reading, and accepted only as UTF-8 without NULs.
- Raw HTML never executes, active tags such as `script` and `style` remain literal, and the reader does not use a web view.
- Normal block and inline image providers are replaced; remote and local image URLs do not load. Inline and defined reference-style Markdown images are converted to selectable not-loaded text with their alt label before parsing.
- External dispatch is limited to clicked absolute HTTP, HTTPS, and email links without URL credentials or raw/percent-decoded control characters.
- Relative Markdown links are handled inside the preview and show a remote-vault explanation without reaching the network, filesystem, or system URL handler.
- Wiki links, tags, footnotes, embeds, and math use private schemes handled locally; generated wiki, tag, footnote, and math references require a random per-preview capability token, so remote-authored forgeries stay blocked.
- Mermaid is labelled source-only and is never executed.
- Syntax highlighting accepts at most 64 KiB, requires an explicit known language, enriches at most 128 labelled blocks per document, and uses a bundled highlight.js build without a DOM or network bridge.
- Math is syntax-validated and accepts at most 4,096 characters and 256 formulas per document. Named and inline footnotes, internal links, and the combined Markdown-image/Obsidian-embed placeholder budget are also count-bounded; invalid and overflow content remains source.
- Third-party package versions are exact and license notices are copied into the app bundle.
- Theme overrides expose heading and task-state semantics to accessibility and keep wide tables in a horizontal scroller.

## Manual evidence recorded

- The current expanded fixture was inspected from launcher through folder list and Markdown preview in forced light and dark appearances.
- Scalar, list-valued, and block-valued properties render as distinct compact rows; callout title and body keep separate lines; a collapsed-source callout remains expanded, and its nested callout uses a second quiet inset rail without disclosure controls or hidden text. Highlighted emphasis remains visible; GFM tables and task markers remain legible.
- The expanded native fixture renders `[?]` as a completed task while keeping `[ ]` incomplete. Selecting its relative `Guides/Setup.md#Install` link shows `Remote Link Not Opened` and explains that RelayBar does not fetch or resolve remote vault files.
- The fixture's trailing `^preview-summary` block identifier is absent from visible and accessible prose, while its two-space continuation is grouped with the numbered footnote rather than leaking into the document body.
- The fixture's table-safe `[[Operations\|Runbook]]` source remains a two-column table and renders only the linked `Runbook` label, without a visible escape or an accidental extra column.
- Inline math stays on the text baseline. Display math renders at its intrinsic size without enlargement and is capped to the reading column; the same formula remains legible in both appearances.
- Explicit Swift code receives appearance-specific syntax colour. The Mermaid block remains source-only with a visible non-execution notice.
- The deliberately long Swift line stays inside an intrinsic-width horizontal scroller. The native accessibility action moved that scroller from its leading edge to its trailing edge without widening the reading column.
- The embed placeholder, blocked remote-image state, literal selectable multi-line `<script>` text, HTML-looking link label, and numbered footnote section remain visible without loading or execution in both appearances.
- The updated native fixture uses a full reference-style image with an Obsidian `640x360` size hint and renders compact, selectable `Image not loaded: A remote chart that is intentionally not fetched` content, retaining the document author's alt text, omitting inert sizing metadata, and never contacting its URL.
- The native fixture renders `#production/relaybar` as a legible inert link in light and dark appearances. Selecting it shows `Tag Not Opened` and explains that RelayBar does not index or search the remote vault.
- The native accessibility tree exposes the document headings as headings, task content and math descriptions, Copy controls, the Mermaid safety description, the blocked image description, and Back/Download controls in reading order.
- Selecting **Copy** changed its accessible title from `Copy code` to `Code copied`, confirming visible local feedback.
- Launcher Return, list focus and arrow selection, Return to open, Space to preview, and Escape to return were exercised in the same build. Returning from preview restored the selected file.
- The Xcode app target build, `git diff --check`, and project-file `plutil -lint` pass after the final renderer changes.
- The pruned Debug bundle received a final native replay in forced light and dark appearances. The retained `github.css` and `github-dark.css` themes both highlighted the Swift fixture correctly, the retained Latin Modern resources rendered inline and display math, and callouts, properties, tables, task states, Mermaid source, blocked images/embeds, literal HTML, and footnotes remained legible and inert.

Task 002 was accepted on 2026-07-24.
