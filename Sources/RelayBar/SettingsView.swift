import AppKit
import SwiftUI

/// In-popover settings screen. Shares the editor screen's navigation idiom so
/// list → settings feels like one surface.
struct SettingsView: View {
    @ObservedObject var launchAtLogin: LaunchAtLoginModel
    @ObservedObject var updates: UpdateModel
    @ObservedObject var backups: BackupModel
    @StateObject private var about: ApplicationAboutModel
    let onBack: () -> Void

    init(
        launchAtLogin: LaunchAtLoginModel,
        updates: UpdateModel,
        backups: BackupModel,
        about: ApplicationAboutModel = ApplicationAboutModel(),
        onBack: @escaping () -> Void
    ) {
        self.launchAtLogin = launchAtLogin
        self.updates = updates
        self.backups = backups
        _about = StateObject(wrappedValue: about)
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            PopoverScrollContainer(fillsViewport: true) {
                VStack(alignment: .leading, spacing: 18) {
                    generalSection
                    backupSection
                    Spacer(minLength: 24)
                    aboutFooter
                }
            }
        }
        .onExitCommand(perform: onBack)
        .onAppear {
            launchAtLogin.refresh()
            updates.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            launchAtLogin.refresh()
            updates.refresh()
        }
        .onDisappear {
            about.cancelTransientState()
            updates.cancelTransientState()
            backups.cancelTransientState()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            CircleIconButton(
                systemName: "chevron.left",
                font: .system(size: 12, weight: .semibold),
                accessibilityLabel: "Back",
                action: onBack
            )

            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("GENERAL")

            VStack(spacing: 0) {
                launchAtLoginRow
                if hasLaunchAtLoginCaption {
                    Divider()
                        .padding(.horizontal, 12)
                    launchAtLoginCaption
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                    .padding(.horizontal, 12)
                automaticUpdatesRow
            }
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )

            Text("A login launch opens RelayBar; profiles marked Start at Launch start automatically.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("BACKUP")

            VStack(spacing: 0) {
                automaticBackupsRow
                Divider()
                    .padding(.horizontal, 12)
                backupFolderRow
                Divider()
                    .padding(.horizontal, 12)
                exportImportRow
            }
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )

            Text("Backups hold your forwarding profiles and saved Remote Files hosts. RelayBar never stores passwords or keys.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var automaticBackupsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Automatic Backups")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Saves a copy after each change and keeps the newest \(BackupFileNaming.retainedAutomaticBackupCount).")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle(
                "Automatic Backups",
                isOn: Binding(
                    get: { backups.isAutomaticBackupEnabled },
                    set: { backups.setAutomaticBackupEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var backupFolderRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(backups.folderDisplayPath ?? "No backup folder")
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(backups.folder?.path ?? "")
                backupStatus
            }

            Spacer(minLength: 8)

            Button("Choose\u{2026}", action: backups.chooseFolder)
                .controlSize(.small)
                .accessibilityLabel("Choose backup folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    @ViewBuilder private var backupStatus: some View {
        if let error = backups.automaticBackupError {
            Text("Last backup failed. \(error)")
                .font(.system(size: 10.5))
                .foregroundStyle(.red)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .help(error)
        } else if let date = backups.lastAutomaticBackupDate {
            Text("Last backup \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        } else {
            Text(backups.folder == nil ? "Choose where automatic backups go" : "No backup yet")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private var exportImportRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button("Export\u{2026}", action: backups.exportBackup)
                    .controlSize(.small)
                    .help("Save your profiles and Remote Files hosts to a file")
                    .accessibilityLabel("Export backup")
                Button("Import\u{2026}", action: backups.importBackup)
                    .controlSize(.small)
                    .help("Restore profiles and Remote Files hosts from a backup file")
                    .accessibilityLabel("Import backup")
                Spacer()
            }

            switch backups.activity {
            case .idle:
                EmptyView()
            case .succeeded(let message):
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(message)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var automaticUpdatesRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Automatically Check for Updates")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Checks about once a week and offers new versions. Nothing installs without you.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle(
                "Automatically Check for Updates",
                isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!updates.isAvailable)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var launchAtLoginRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at Login")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Open RelayBar when you log in")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Bound to the authoritative system status, including when the
            // latest register or unregister operation surfaced an error.
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLogin.state.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var aboutFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(about.metadata.displayText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(about.metadata.accessibilityLabel)

                Button(action: about.copyVersion) {
                    Image(systemName: about.didCopyVersion ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentTransition(.identity)
                }
                .buttonStyle(.plain)
                .help("Copy version and build")
                .accessibilityLabel("Copy version and build")

                Spacer()
            }

            HStack(spacing: 7) {
                footerLink(
                    "Check for Updates…",
                    isEnabled: updates.canCheckForUpdates,
                    action: updates.checkForUpdates
                )
                    .accessibilityHint("Checks the RelayBar update feed")

                updateStatus
            }

            HStack(spacing: 5) {
                footerLink("Website", action: about.openWebsite)
                    .accessibilityLabel("Open RelayBar website in browser")
                Text("·")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                footerLink("GitHub", action: about.openRepository)
                    .accessibilityLabel("Open RelayBar on GitHub in browser")
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var updateStatus: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking…")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Checking for updates")
        case .upToDate:
            Text("You're up to date.")
                .accessibilityLabel("RelayBar is up to date")
        case .failed:
            Text("Couldn't check. Try again.")
                .accessibilityLabel("Couldn't check for updates. Try again.")
        case .waitingForTunnels(let count):
            let noun = count == 1 ? "tunnel" : "tunnels"
            Text("Update ready. Stop \(count) \(noun) to finish.")
                .accessibilityLabel(
                    "Update ready. Stop \(count) \(noun) to finish installing."
                )
        }
    }

    private func footerLink(
        _ title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.system(size: 10.5))
            .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
            .buttonStyle(.plain)
            .disabled(!isEnabled)
    }

    private var hasLaunchAtLoginCaption: Bool {
        switch launchAtLogin.state {
        case .notRegistered, .enabled: false
        case .requiresApproval, .notFound, .error: true
        }
    }

    @ViewBuilder private var launchAtLoginCaption: some View {
        switch launchAtLogin.state {
        case .notRegistered, .enabled:
            EmptyView()
        case .requiresApproval:
            Button(action: launchAtLogin.openLoginItemsSettings) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("Needs approval — open Login Items settings")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Login Items settings to approve launching at login")
        case .notFound:
            Text("macOS couldn’t find this copy of RelayBar as a login item.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        case .error(status: _, message: let message):
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.red)
                .lineLimit(3)
                .help(message)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }
}
