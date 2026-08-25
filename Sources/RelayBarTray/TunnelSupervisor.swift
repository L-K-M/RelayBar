import Foundation
import RelayBarCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One row of tray state: the profile plus its observed lifecycle phase.
struct SupervisedTunnel: Sendable {
    let profile: Tunnel
    let phase: TunnelPhase
}

/// Starts, stops, retries, and reports ssh masters for the saved profiles.
///
/// All mutable state is confined to a serial queue; UI callbacks receive an
/// immutable snapshot and are responsible for hopping to the main loop.
final class TunnelSupervisor: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "relaybar-tray.supervisor")
    private let sshExecutableURL: URL
    private let maxRetryAttempts = TunnelRetryPolicy.defaultMaxAttempts
    private let stopGraceInterval: TimeInterval = 3

    private var profiles: [UUID: Tunnel] = [:]
    private var desiredIDs: Set<UUID> = []
    private var processes: [UUID: Process] = [:]
    private var controlDirectories: [UUID: URL] = [:]
    private var stderrFiles: [UUID: FileHandle] = [:]
    private var retryAttempts: [UUID: Int] = [:]
    private var phases: [UUID: TunnelPhase] = [:]
    private var stopTimers: [UUID: DispatchWorkItem] = [:]

    /// Invoked on `stateQueue` whenever any phase changes.
    var onStateChange: (@Sendable () -> Void)?

    init(sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh")) {
        self.sshExecutableURL = sshExecutableURL
    }

    // MARK: - Reading state

    func snapshot() -> [SupervisedTunnel] {
        stateQueue.sync {
            profiles.values.map { profile in
                SupervisedTunnel(
                    profile: profile,
                    phase: phases[profile.id] ?? .stopped
                )
            }
            .sorted { $0.profile.displayName.localizedStandardCompare($1.profile.displayName) == .orderedAscending }
        }
    }

    // MARK: - Profile management

    func replaceProfiles(_ tunnels: [Tunnel]) {
        stateQueue.async { [self] in
            profiles = Dictionary(uniqueKeysWithValues: tunnels.map { ($0.id, $0) })
            for tunnel in tunnels where phases[tunnel.id] == nil {
                phases[tunnel.id] = .stopped
            }
            emitChange()
        }
    }

    /// Refreshes definitions for stopped profiles and drops deleted ones.
    /// Running masters keep their original argv by design: reloading must
    /// never silently rewrite live forwarding rules.
    func reloadProfiles(_ tunnels: [Tunnel]) {
        stateQueue.async { [self] in
            let fresh = Dictionary(uniqueKeysWithValues: tunnels.map { ($0.id, $0) })
            for id in fresh.keys where !desiredIDs.contains(id) && phases[id] == nil {
                phases[id] = .stopped
            }
            profiles.merge(fresh) { current, updated in
                desiredIDs.contains(current.id) ? current : updated
            }
            emitChange()
        }
    }

    // MARK: - Lifecycle

    func start(profileID id: UUID) {
        stateQueue.async { [self] in
            guard
                let tunnel = profiles[id],
                processes[id] == nil
            else { return }
            launch(tunnel)
        }
    }

    func stop(profileID id: UUID) {
        stateQueue.async { [self] in
            terminate(id: id)
        }
    }

    func stopAll() {
        stateQueue.sync {
            for id in desiredIDs {
                terminate(id:)
            }
        }
    }

    // MARK: - Launch path

    /// Runs on `stateQueue`. A start marks the profile desired and spawns the
    /// master; failures enter the shared retry schedule instead of surfacing
    /// as a dead toggle.
    private func launch(_ tunnel: Tunnel) {
        // Reloaded definitions bypass the store's load-time filter, so the
        // safety gate belongs on every start path.
        guard tunnel.isSafeToRun else {
            phases[tunnel.id] = .failed("Profile is invalid or unsafe to run.")
            emitChange()
            return
        }

        cancelStopTimer(tunnel.id)
        desiredIDs.insert(tunnel.id)
        retryAttempts[tunnel.id] = 0
        phases[tunnel.id] = .starting
        emitChange()

        do {
            try FileManager.default.createDirectory(
                at: Self.temporaryRoot,
                withIntermediateDirectories: true
            )
        } catch {
            scheduleRetry(profileID: tunnel.id, message: error.localizedDescription)
            return
        }

        spawnMaster(tunnel)
    }

    private func spawnMaster(_ tunnel: Tunnel) {
        let controlLocations: SSHControlLocations
        do {
            controlLocations = try SSHControlPath.create(in: Self.temporaryRoot)
        } catch {
            scheduleRetry(profileID: tunnel.id, message: error.localizedDescription)
            return
        }

        controlDirectories[tunnel.id] = controlLocations.directory

        let process = Process()
        process.executableURL = sshExecutableURL
        process.arguments = SSHMasterInvocation.arguments(
            tunnel: tunnel,
            controlSocketPath: controlLocations.socket.path
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        let stderrHandle = openStderrCapture(for: tunnel.id)
        process.standardError = stderrHandle

        let tunnelID = tunnel.id
        process.terminationHandler = { [weak self] finishedProcess in
            guard let self else { return }
            self.stateQueue.async {
                self.handleTermination(
                    of: finishedProcess,
                    for: tunnelID,
                    status: finishedProcess.terminationStatus
                )
            }
        }

        processes[tunnel.id] = process
        stderrFiles[tunnel.id] = stderrHandle

        do {
            try process.run()
        } catch {
            handleTermination(of: process, for: tunnel.id, status: -1)
        }
    }

    private func openStderrCapture(for id: UUID) -> FileHandle {
        let directory = controlDirectories[id]?.path ?? Self.temporaryRoot.path
        let url = URL(fileURLWithPath: directory).appendingPathComponent("stderr")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        return FileHandle(forWritingAtPath: url.path) ?? FileHandle.nullDevice
    }

    // MARK: - Termination and retry

    private func handleTermination(
        of process: Process,
        for id: UUID,
        status: Int32
    ) {
        guard processes[id] === process else { return } // already replaced or stopped

        // Read the failure text before tearing down its capture file.
        let message = status == 0
            ? nil
            : trimmedStderrTail(id) ?? "ssh exited unexpectedly (status \(status))."

        closeStderrCapture(id)
        cleanupControlDirectory(id)
        processes[id] = nil
        removeStopTimer(id)

        guard desiredIDs.contains(id) else {
            phases[id] = .stopped
            emitChange()
            return
        }

        scheduleRetry(profileID: id, message: message ?? "ssh exited cleanly while still desired.")
    }

    private func scheduleRetry(profileID id: UUID, message: String) {
        let attempt = (retryAttempts[id] ?? 0) + 1
        guard attempt <= maxRetryAttempts else {
            desiredIDs.remove(id)
            phases[id] = .failed("\(message) Stopped after \(maxRetryAttempts) attempts.")
            emitChange()
            notifyFailure(message: phases[id].map(phaseSummary) ?? message)
            return
        }

        retryAttempts[id] = attempt
        let delay = TunnelRetryPolicy.delay(for: attempt)
        phases[id] = .retrying(attempt: attempt, maxAttempts: maxRetryAttempts, delay: delay, message: message)
        emitChange()

        stateQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard
                let self,
                self.desiredIDs.contains(id),
                self.processes[id] == nil,
                let tunnel = self.profiles[id],
                tunnel.isSafeToRun
            else { return }
            self.spawnMaster(tunnel)
        }
    }

    /// Synchronous stop used by both the menu action and shutdown. Escalates
    /// to SIGKILL only if the master ignores SIGTERM past the grace period.
    private func terminate(id: UUID) {
        guard let process = processes[id] else {
            cancelPendingRetry(id)
            desiredIDs.remove(id)
            // A failed profile keeps its message so the menu can offer a
            // retry with context; everything else reports stopped.
            if case .failed = phases[id] {} else {
                phases[id] = .stopped
            }
            emitChange()
            return
        }

        desiredIDs.remove(id)
        phases[id] = .stopped
        emitChange()

        kill(process.processIdentifier, SIGTERM)

        let timer = DispatchWorkItem { [weak self, weak process] in
            guard
                let self,
                let process,
                process.isRunning
            else { return }
            kill(process.processIdentifier, SIGKILL)
        }
        stopTimers[id] = timer
        stateQueue.asyncAfter(deadline: .now() + stopGraceInterval, execute: timer)
    }

    private func cancelPendingRetry(_ id: UUID) {
        retryAttempts[id] = nil
    }

    private func cancelStopTimer(_ id: UUID) {
        stopTimers[id]?.cancel()
        stopTimers[id] = nil
    }

    private func removeStopTimer(_ id: UUID) {
        stopTimers[id] = nil
    }

    // MARK: - Cleanup helpers

    private func closeStderrCapture(_ id: UUID) {
        try? stderrFiles[id]?.close()
        stderrFiles[id] = nil
    }

    private func trimmedStderrTail(_ id: UUID) -> String? {
        guard let handle = stderrReadHandle(id) else { return nil }
        defer { try? handle.close() }

        let maximumBytes = 2_048
        let length = (try? handle.seekToEnd()) ?? 0
        let offset = max(0, length - UInt64(maximumBytes))
        try? handle.seek(toOffset: offset)
        let data = handle.readData(ofLength: maximumBytes)
        let text = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .suffix(3)
            .joined(separator: " · ")
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func stderrReadHandle(_ id: UUID) -> FileHandle? {
        guard
            let directory = controlDirectories[id]
        else { return nil }
        let url = directory.appendingPathComponent("stderr")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return FileHandle(forReadingAtPath: url.path)
    }

    private func cleanupControlDirectory(_ id: UUID) {
        guard let directory = controlDirectories[id] else { return }
        try? FileManager.default.removeItem(at: directory)
        controlDirectories[id] = nil
    }

    private func phaseSummary(_ phase: TunnelPhase) -> String {
        switch phase {
        case .failed(let message): message
        default: ""
        }
    }

    private func notifyFailure(message: String) {
        // Best effort desktop notification; absence of a notifier is fine.
        let url = URL(fileURLWithPath: "/usr/bin/notify-send")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let process = Process()
        process.executableURL = url
        process.arguments = ["-a", "RelayBar", "RelayBar tunnel failed", message]
        try? process.run()
    }

    private func emitChange() {
        onStateChange?()
    }

    static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "relaybar-tray", isDirectory: true
        )
    }
}
