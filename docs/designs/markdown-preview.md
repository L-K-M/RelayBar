# Read-only Markdown

RelayBar treats Markdown as a document preview, not a remote editing mode or vault.

## Reading model

- Open a Markdown row by double-clicking, pressing Command-Down, choosing **Preview**, or pressing Space.
- Keep the Remote Files list mounted behind the preview so returning preserves selection and scroll position.
- Use the same quiet toolbar as image preview: **Back**, filename, and **Download**.
- Center a selectable reading column inside the available window.
- Present properties and quotes/callouts in restrained containers, code in horizontally scrollable blocks, and math as native vector-like images.
- Keep wide tables inside their own horizontal scroller and expose headings and task state through native accessibility traits.

## Compatibility model

RelayBar starts with CommonMark and GitHub-flavoured Markdown, then translates a bounded subset of Obsidian reading syntax before parsing:

| Source convention | Reading behavior |
| --- | --- |
| YAML frontmatter | A compact **Properties** callout; common list/block values stay grouped with their key |
| `> [!type] Title` | A labelled callout container |
| `==text==` | Markers disappear and emphasis is preserved |
| `%% comment %%` | Hidden outside code |
| `- [?] task` | Completed task state; original marker stays in the downloadable source |
| `[[target\|label]]` | Labelled inert wiki link |
| `[label](Note.md#Heading)` | Labelled inert remote-vault link |
| `![[target]]` | “Embedded file not loaded” state |
| `[^note]` and `^[inline note]` | Superscript reference plus a footnotes section |
| `$…$` and `$$…$$` | Native local math rendering |
| fenced language | Bounded local syntax highlighting |
| fenced `mermaid` | Selectable source with a non-execution notice |

The compatibility pass does not rewrite inline code, including code spans across soft line breaks, or fenced and indented code, including code nested in blockquotes, callouts, and list items. The original source remains available for download unchanged.

## Safety model

- The Markdown transfer and decoder enforce a 2 MiB limit.
- Only UTF-8 without NULs is accepted.
- MarkdownUI and swift-cmark's cmark-gfm products render the document natively; RelayBar does not use a web view.
- HTML-looking spans are escaped before parsing, so active tags such as `script` and `style` stay literal and selectable, including multi-line tags and tags in Markdown link labels, while valid web/mail angle autolinks remain links.
- Custom image providers make normal Markdown images inert. They only recognize RelayBar's private math URL format.
- Wiki links, footnotes, and math use per-preview capability URLs that never reach macOS. Private-looking URLs supplied by the remote document do not have the current preview token and remain blocked.
- Only clicked absolute HTTP, HTTPS, and email URLs reach the system handler. Relative Markdown references stay inside RelayBar and explain that remote-vault resolution is unavailable.
- HighlighterSwift runs a bundled highlight.js build in JavaScriptCore as a local formatter. It sees at most 64 KiB from each explicitly labelled, known-language code block and enriches at most 128 labelled blocks per document; overflow code stays plain. It has no DOM or network bridge.
- SwiftMath parses at most 4,096 characters per formula and at most 256 formulas per document. RelayBar validates syntax before emitting a private math reference, bounds the resulting image dimensions, and preserves invalid, rejected, or overflow formulas as source.
- Compatibility enrichment is also capped at 1,024 extracted footnotes, 2,048 internal wiki/footnote links, and 512 embed placeholders per document. Overflow content remains readable Markdown instead of disappearing.
- Mermaid stays source-only because executing document-provided diagram code would add an avoidable active-content surface.

## Open-source baseline

The reader pins MarkdownUI 2.4.1, HighlighterSwift 3.1.0, and SwiftMath 1.7.3. MarkdownUI brings NetworkImage 6.0.1 and swift-cmark 0.8.0 transitively, but RelayBar replaces its network image providers so remote images are never requested. The 2026-07-24 dependency audit confirmed that all three direct pins match their upstream current stable release or tag.

The newer Textual and SwiftMarkdownEngine projects informed the feature audit, but their current minimum macOS versions exceed RelayBar's macOS 13 promise. The selected stack preserves that compatibility while keeping the rendering boundary native and testable.
