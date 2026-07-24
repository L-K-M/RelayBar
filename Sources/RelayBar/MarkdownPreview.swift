import AppKit
import Foundation
import MarkdownUI
import SwiftUI

/// `MarkdownContent` is not annotated Sendable upstream, but RelayBar constructs
/// it once off-main and only exposes immutable values afterward.
struct RemoteMarkdownDocument: @unchecked Sendable {
    let referenceToken: String
    let content: MarkdownContent

    var plainText: String {
        content.renderPlainText()
    }
}

enum RemoteMarkdownDecoder {
    static let maximumByteCount = 2 * 1_024 * 1_024

    static func load(
        contentsOf url: URL,
        renderingSourceWith renderer: @escaping @Sendable (String, String) throws -> String = {
            ObsidianMarkdownCompatibility.renderSource(
                $0,
                referenceToken: $1,
                mathValidator: { formula in
                    RemoteMathRenderer.canParse(formula)
                }
            )
        }
    ) async throws -> RemoteMarkdownDocument {
        let referenceToken = UUID().uuidString.lowercased()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try readBoundedData(from: url)
            try Task.checkCancellation()
            let source = try decode(data)
            try Task.checkCancellation()
            let renderedSource = try renderer(source, referenceToken)
            try Task.checkCancellation()
            return RemoteMarkdownDocument(
                referenceToken: referenceToken,
                content: MarkdownContent(renderedSource)
            )
        }
        return try await withTaskCancellationHandler {
            let document = try await worker.value
            try Task.checkCancellation()
            return document
        } onCancel: {
            worker.cancel()
        }
    }

    static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumByteCount else {
            throw RemoteFileError.markdownTooLarge
        }
        guard var source = String(data: data, encoding: .utf8) else {
            throw RemoteFileError.invalidMarkdownEncoding
        }
        guard !source.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw RemoteFileError.invalidMarkdownEncoding
        }
        if source.unicodeScalars.first?.value == 0xFEFF {
            source.removeFirst()
        }
        return source
    }

    private static func readBoundedData(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumByteCount + 1) ?? Data()
        guard data.count <= maximumByteCount else {
            throw RemoteFileError.markdownTooLarge
        }
        return data
    }
}

enum SafeMarkdownLinkPolicy {
    enum Decision: Equatable {
        case external
        case wiki(String)
        case tag(String)
        case footnote(String)
        case internalMarkdown(String)
        case blocked
    }

    static func decision(for url: URL, referenceToken: String) -> Decision {
        if
            let wiki = ObsidianMarkdownCompatibility.internalValue(
                from: url,
                expectedScheme: "relaybar-wiki",
                referenceToken: referenceToken
            ),
            wiki.kind == "open"
        {
            return .wiki(wiki.value)
        }
        if
            let tag = ObsidianMarkdownCompatibility.internalValue(
                from: url,
                expectedScheme: "relaybar-tag",
                referenceToken: referenceToken
            ),
            tag.kind == "open"
        {
            return .tag(tag.value)
        }
        if
            let footnote = ObsidianMarkdownCompatibility.internalValue(
                from: url,
                expectedScheme: "relaybar-footnote",
                referenceToken: referenceToken
            ),
            footnote.kind == "note"
        {
            return .footnote(footnote.value)
        }
        if allows(url) {
            return .external
        }
        if let reference = internalMarkdownReference(from: url) {
            return .internalMarkdown(reference)
        }
        return .blocked
    }

    static func allows(_ url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            ["http", "https", "mailto"].contains(scheme),
            decodedWithoutControls(url.absoluteString) != nil
        else {
            return false
        }

        if scheme == "mailto" {
            return hasMailRecipient(in: url.absoluteString)
        }
        return url.user == nil
            && url.password == nil
            && url.host?.isEmpty == false
    }

    private static func hasMailRecipient(in value: String) -> Bool {
        guard let separator = value.firstIndex(of: ":") else {
            return false
        }
        let payload = value[value.index(after: separator)...]
        let recipient = payload.prefix { $0 != "?" && $0 != "#" }
        return !recipient.isEmpty
    }

    private static func internalMarkdownReference(from url: URL) -> String? {
        let rawReference = url.relativeString
        guard
            let decodedReference = decodedWithoutControls(rawReference),
            url.scheme == nil,
            url.host == nil,
            url.user == nil,
            url.password == nil,
            !rawReference.isEmpty,
            !rawReference.hasPrefix("/"),
            !rawReference.hasPrefix("//"),
            !url.path.isEmpty || url.fragment != nil,
            rawReference.utf8.count <= ObsidianMarkdownCompatibility
                .maximumFormulaCharacterCount
        else {
            return nil
        }
        return decodedReference
    }

    private static func decodedWithoutControls(_ value: String) -> String? {
        guard
            let decoded = value.removingPercentEncoding,
            !value.unicodeScalars.contains(where: isControl),
            !decoded.unicodeScalars.contains(where: isControl)
        else {
            return nil
        }
        return decoded
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.controlCharacters.contains(scalar)
            || CharacterSet.newlines.contains(scalar)
    }
}

struct SafeRemoteMarkdownView: View {
    let document: RemoteMarkdownDocument

    @State private var linkAlert: MarkdownLinkAlert?

    var body: some View {
        ScrollView {
            Markdown(document.content)
                .markdownTheme(.relayBar)
                .markdownImageProvider(
                    SafeMarkdownImageProvider(referenceToken: document.referenceToken)
                )
                .markdownInlineImageProvider(
                    SafeMarkdownInlineImageProvider(referenceToken: document.referenceToken)
                )
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        switch SafeMarkdownLinkPolicy.decision(
                            for: url,
                            referenceToken: document.referenceToken
                        ) {
                        case .external:
                            return .systemAction(url)
                        case .wiki(let target):
                            linkAlert = .wiki(target)
                            return .handled
                        case .tag(let tag):
                            linkAlert = .tag(tag)
                            return .handled
                        case .footnote(let label):
                            linkAlert = .footnote(label)
                            return .handled
                        case .internalMarkdown(let target):
                            linkAlert = .internalMarkdown(target)
                            return .handled
                        case .blocked:
                            linkAlert = .blocked
                            return .handled
                        }
                    }
                )
                .textSelection(.enabled)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert(item: $linkAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private extension Theme {
    static var relayBar: Theme {
        Theme.gitHub
            .heading1 { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: VStack(alignment: .leading, spacing: 0) {
                            mainThreadConfiguration.value.label
                                .relativePadding(.bottom, length: .em(0.3))
                                .relativeLineSpacing(.em(0.125))
                                .markdownMargin(top: 24, bottom: 16)
                                .markdownTextStyle {
                                    FontWeight(.semibold)
                                    FontSize(.em(2))
                                }
                                .accessibilityAddTraits(.isHeader)
                            Divider().opacity(0.55)
                        }
                    )
                }
            }
            .heading2 { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: VStack(alignment: .leading, spacing: 0) {
                            mainThreadConfiguration.value.label
                                .relativePadding(.bottom, length: .em(0.3))
                                .relativeLineSpacing(.em(0.125))
                                .markdownMargin(top: 24, bottom: 16)
                                .markdownTextStyle {
                                    FontWeight(.semibold)
                                    FontSize(.em(1.5))
                                }
                                .accessibilityAddTraits(.isHeader)
                            Divider().opacity(0.55)
                        }
                    )
                }
            }
            .heading3 { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: mainThreadConfiguration.value.label
                            .relativeLineSpacing(.em(0.125))
                            .markdownMargin(top: 24, bottom: 16)
                            .markdownTextStyle {
                                FontWeight(.semibold)
                                FontSize(.em(1.25))
                            }
                            .accessibilityAddTraits(.isHeader)
                    )
                }
            }
            .heading4 { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: mainThreadConfiguration.value.label
                            .relativeLineSpacing(.em(0.125))
                            .markdownMargin(top: 24, bottom: 16)
                            .markdownTextStyle {
                                FontWeight(.semibold)
                            }
                            .accessibilityAddTraits(.isHeader)
                    )
                }
            }
            .heading5 { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: mainThreadConfiguration.value.label
                            .relativeLineSpacing(.em(0.125))
                            .markdownMargin(top: 24, bottom: 16)
                            .markdownTextStyle {
                                FontWeight(.semibold)
                                FontSize(.em(0.875))
                            }
                            .accessibilityAddTraits(.isHeader)
                    )
                }
            }
            .heading6 { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: mainThreadConfiguration.value.label
                            .relativeLineSpacing(.em(0.125))
                            .markdownMargin(top: 24, bottom: 16)
                            .markdownTextStyle {
                                FontWeight(.semibold)
                                FontSize(.em(0.85))
                                ForegroundColor(.secondary)
                            }
                            .accessibilityAddTraits(.isHeader)
                    )
                }
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: 3)
                    configuration.label
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor.opacity(0.065))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.accentColor.opacity(0.12))
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .taskListMarker { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: Image(
                            systemName: mainThreadConfiguration.value.isCompleted
                                ? "checkmark.square.fill"
                                : "square"
                        )
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            mainThreadConfiguration.value.isCompleted
                                ? Color.accentColor
                                : Color.secondary
                        )
                        .imageScale(.small)
                        .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                        .accessibilityLabel(
                            mainThreadConfiguration.value.isCompleted
                                ? "Completed task"
                                : "Incomplete task"
                        )
                    )
                }
            }
            .codeBlock { configuration in
                let content = configuration.content
                let language = configuration.language
                MainActor.assumeIsolated {
                    MarkdownCodeBlock(content: content, language: language)
                }
            }
            .table { configuration in
                let mainThreadConfiguration = MainThreadValue(value: configuration)
                MainActor.assumeIsolated {
                    MainThreadView(
                        content: ScrollView(.horizontal) {
                            mainThreadConfiguration.value.label
                                .fixedSize(horizontal: true, vertical: true)
                                .markdownTableBorderStyle(
                                    .init(color: Color.primary.opacity(0.14))
                                )
                                .markdownTableBackgroundStyle(
                                    .alternatingRows(
                                        Color.clear,
                                        Color.primary.opacity(0.035)
                                    )
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .markdownMargin(top: 0, bottom: 16)
                        .accessibilityHint("Scroll horizontally to read additional columns")
                    )
                }
            }
    }
}

/// MarkdownUI's theme callbacks predate Swift's global-actor annotations but
/// SwiftUI evaluates them on the main thread. This wrapper makes that contract
/// explicit at the narrow callback boundary.
private struct MainThreadValue<Value>: @unchecked Sendable {
    let value: Value
}

private struct MainThreadView<Content: View>: View, @unchecked Sendable {
    let content: Content

    var body: some View {
        content
    }
}

private struct MarkdownLinkAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static func wiki(_ target: String) -> MarkdownLinkAlert {
        MarkdownLinkAlert(
            title: "Wiki Link Not Opened",
            message:
                "“\(target)” is shown as a link, but RelayBar does not resolve remote vault links or fetch linked files."
        )
    }

    static func footnote(_ label: String) -> MarkdownLinkAlert {
        MarkdownLinkAlert(
            title: "Footnote \(label)",
            message: "The footnote is listed at the end of this document."
        )
    }

    static func tag(_ tag: String) -> MarkdownLinkAlert {
        MarkdownLinkAlert(
            title: "Tag Not Opened",
            message:
                "“#\(tag)” is shown as a tag, but RelayBar does not index or search the remote vault."
        )
    }

    static func internalMarkdown(_ target: String) -> MarkdownLinkAlert {
        MarkdownLinkAlert(
            title: "Remote Link Not Opened",
            message:
                "“\(target)” refers to content in the remote vault. RelayBar shows the link but does not fetch or resolve remote files."
        )
    }

    static let blocked = MarkdownLinkAlert(
        title: "Link Not Opened",
        message: "RelayBar only opens absolute HTTP, HTTPS, and email links."
    )
}

private struct MarkdownCodeBlock: View {
    let content: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(languageLabel)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                CopyCodeButton(content: content)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            if isMermaid {
                HStack(spacing: 7) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text("Diagram source only — remote Mermaid code is not executed")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
                .accessibilityLabel("Mermaid diagram source only. Code is not executed.")
            }

            Divider()

            ScrollView(.horizontal) {
                activeHighlighter.highlightCode(content, language: normalizedLanguage)
                    .fixedSize(horizontal: true, vertical: true)
                    .relativeLineSpacing(.em(0.225))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.09))
        )
        .markdownMargin(top: 0, bottom: 16)
    }

    private var languageLabel: String {
        normalizedLanguage ?? "plain text"
    }

    private var normalizedLanguage: String? {
        let language = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let language, !language.isEmpty else { return nil }
        return language
    }

    private var activeHighlighter: RelayBarCodeSyntaxHighlighter {
        colorScheme == .dark
            ? RelayBarCodeSyntaxHighlighter.dark
            : RelayBarCodeSyntaxHighlighter.light
    }

    private var isMermaid: Bool {
        normalizedLanguage?
            .split(whereSeparator: \.isWhitespace)
            .first == "mermaid"
    }
}

private struct CopyCodeButton: View {
    let content: String

    @State private var didCopy = false
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(content, forType: .string) else { return }
            feedbackTask?.cancel()
            didCopy = true
            feedbackTask = Task {
                do {
                    try await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    didCopy = false
                } catch {
                    // A newer copy or view dismissal owns the feedback state.
                }
            }
        } label: {
            Label(
                didCopy ? "Copied" : "Copy",
                systemImage: didCopy ? "checkmark" : "doc.on.doc"
            )
            .font(.system(size: 10.5, weight: .medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didCopy ? "Code copied" : "Copy code")
        .onDisappear {
            feedbackTask?.cancel()
            feedbackTask = nil
        }
    }
}
