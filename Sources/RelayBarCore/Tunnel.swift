import Foundation

public enum ForwardingRuleKind: String, Codable, CaseIterable, Sendable {
    case local
    case localDynamic
    case remote
    case remoteDynamic

    public var label: String {
        switch self {
        case .local: "Local"
        case .localDynamic: "Local SOCKS"
        case .remote: "Remote"
        case .remoteDynamic: "Remote SOCKS"
        }
    }

    public var sshOption: String {
        switch self {
        case .local: "-L"
        case .localDynamic: "-D"
        case .remote, .remoteDynamic: "-R"
        }
    }

    public var listensRemotely: Bool {
        self == .remote || self == .remoteDynamic
    }

    public var isDynamic: Bool {
        self == .localDynamic || self == .remoteDynamic
    }
}

public struct TCPListenEndpoint: Codable, Equatable, Hashable, Sendable {
    public var bindAddress: String?
    public var port: Int

    public init(bindAddress: String? = nil, port: Int) {
        self.bindAddress = bindAddress
        self.port = port
    }

    public var specification: String {
        guard let bindAddress else { return String(port) }
        return "\(SSHForwardingFormat.bracketIPv6(bindAddress)):\(port)"
    }

    public var displayText: String {
        let host = bindAddress.flatMap { $0.isEmpty ? nil : $0 } ?? "localhost"
        return "\(host):\(port)"
    }

    public var exposesBeyondLoopback: Bool {
        guard let bindAddress else { return false }
        let normalized = SSHForwardingFormat.unbracket(bindAddress).lowercased()
        return !["localhost", "127.0.0.1", "::1"].contains(normalized)
    }
}

public struct ForwardListenEndpoint: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case tcp
        case unix
    }

    public var kind: Kind
    public var tcp: TCPListenEndpoint?
    public var path: String?

    public static func tcp(bindAddress: String? = nil, port: Int) -> ForwardListenEndpoint {
        ForwardListenEndpoint(
            kind: .tcp,
            tcp: TCPListenEndpoint(bindAddress: bindAddress, port: port),
            path: nil
        )
    }

    public static func unix(path: String) -> ForwardListenEndpoint {
        ForwardListenEndpoint(kind: .unix, tcp: nil, path: path)
    }

    public var specification: String {
        switch kind {
        case .tcp: tcp?.specification ?? ""
        case .unix: path ?? ""
        }
    }

    public var displayText: String {
        switch kind {
        case .tcp: tcp?.displayText ?? "Invalid TCP listener"
        case .unix: path ?? "Invalid Unix socket"
        }
    }

    public var isStructurallyValid: Bool {
        switch kind {
        case .tcp:
            tcp != nil && path == nil
        case .unix:
            tcp == nil && path != nil
        }
    }
}

public struct TCPDestinationEndpoint: Codable, Equatable, Hashable, Sendable {
    public var host: String
    public var port: Int

    public var specification: String {
        "\(SSHForwardingFormat.bracketIPv6(host)):\(port)"
    }

    public var displayText: String {
        "\(host):\(port)"
    }
}

public struct ForwardDestinationEndpoint: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case tcp
        case unix
    }

    public var kind: Kind
    public var tcp: TCPDestinationEndpoint?
    public var path: String?

    public static func tcp(host: String, port: Int) -> ForwardDestinationEndpoint {
        ForwardDestinationEndpoint(
            kind: .tcp,
            tcp: TCPDestinationEndpoint(host: host, port: port),
            path: nil
        )
    }

    public static func unix(path: String) -> ForwardDestinationEndpoint {
        ForwardDestinationEndpoint(kind: .unix, tcp: nil, path: path)
    }

    public var specification: String {
        switch kind {
        case .tcp: tcp?.specification ?? ""
        case .unix: path ?? ""
        }
    }

    public var displayText: String {
        switch kind {
        case .tcp: tcp?.displayText ?? "Invalid TCP destination"
        case .unix: path ?? "Invalid Unix socket"
        }
    }

    public var isStructurallyValid: Bool {
        switch kind {
        case .tcp:
            tcp != nil && path == nil
        case .unix:
            tcp == nil && path != nil
        }
    }
}

public struct ForwardingRule: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var kind: ForwardingRuleKind
    public var listen: ForwardListenEndpoint
    public var destination: ForwardDestinationEndpoint?

    public init(
        id: UUID = UUID(),
        kind: ForwardingRuleKind,
        listen: ForwardListenEndpoint,
        destination: ForwardDestinationEndpoint? = nil
    ) {
        self.id = id
        self.kind = kind
        self.listen = listen
        self.destination = destination
    }

    public static func localTCP(
        id: UUID = UUID(),
        bindAddress: String? = nil,
        port: Int,
        destinationHost: String,
        destinationPort: Int
    ) -> ForwardingRule {
        ForwardingRule(
            id: id,
            kind: .local,
            listen: .tcp(bindAddress: bindAddress, port: port),
            destination: .tcp(host: destinationHost, port: destinationPort)
        )
    }

    public var specification: String {
        if kind.isDynamic {
            return listen.specification
        }
        return "\(listen.specification):\(destination?.specification ?? "")"
    }

    public var sshArguments: [String] {
        [kind.sshOption, specification]
    }

    public var createdLocalSocketPath: String? {
        guard kind == .local, listen.kind == .unix else { return nil }
        return listen.path
    }

    public var displaySummary: String {
        switch kind {
        case .local:
            "\(listen.displayText) → \(destination?.displayText ?? "Invalid destination")"
        case .localDynamic:
            "\(listen.displayText) → SOCKS via server"
        case .remote:
            "\(listen.displayText) ⇠ \(destination?.displayText ?? "Invalid destination")"
        case .remoteDynamic:
            "\(listen.displayText) ⇠ SOCKS via Mac"
        }
    }

    public func displaySummary(runtimePort: Int?) -> String {
        guard
            kind.listensRemotely,
            case .tcp = listen.kind,
            listen.tcp?.port == 0,
            let runtimePort
        else {
            return displaySummary
        }

        var resolved = self
        resolved.listen.tcp?.port = runtimePort
        return resolved.displaySummary
    }

    public func copyableListenEndpoint(runtimePort: Int?) -> String? {
        switch listen.kind {
        case .unix:
            return listen.path
        case .tcp:
            guard var endpoint = listen.tcp else { return nil }
            if endpoint.port == 0 {
                guard let runtimePort else { return nil }
                endpoint.port = runtimePort
            }
            return endpoint.displayText
        }
    }

    public var localBrowserURL: URL? {
        guard
            kind == .local,
            listen.kind == .tcp,
            let endpoint = listen.tcp
        else {
            return nil
        }

        var host = endpoint.bindAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        host = SSHForwardingFormat.unbracket(host)
        if host.isEmpty || ["*", "0.0.0.0", "::"].contains(host.lowercased()) {
            host = "localhost"
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host.contains(":") ? "[\(host)]" : host
        components.port = endpoint.port
        components.path = "/"
        return components.url
    }

    public var isValid: Bool {
        guard listen.isStructurallyValid else { return false }

        switch listen.kind {
        case .tcp:
            guard let tcp = listen.tcp else { return false }
            let validPortRange = kind.listensRemotely ? 0...65_535 : 1...65_535
            guard
                validPortRange.contains(tcp.port),
                SSHArgumentPolicy.isValidBindAddress(tcp.bindAddress)
            else {
                return false
            }
        case .unix:
            guard
                !kind.isDynamic,
                let path = listen.path,
                SSHArgumentPolicy.isValidSocketPath(path)
            else {
                return false
            }
        }

        if kind.isDynamic {
            return destination == nil
        }

        guard let destination, destination.isStructurallyValid else { return false }
        switch destination.kind {
        case .tcp:
            guard let tcp = destination.tcp else { return false }
            return SSHArgumentPolicy.isValidDestinationHost(tcp.host)
                && (1...65_535).contains(tcp.port)
        case .unix:
            guard let path = destination.path else { return false }
            return SSHArgumentPolicy.isValidSocketPath(path)
        }
    }
}

public enum ReverseSOCKSPolicy: Equatable, Sendable {
    case any
    case none
    case allow([String])

    public var sshValue: String {
        switch self {
        case .any: "any"
        case .none: "none"
        case .allow(let destinations): destinations.joined(separator: " ")
        }
    }

    public var displayText: String {
        switch self {
        case .any: "Any destination"
        case .none: "No destinations"
        case .allow(let destinations): destinations.joined(separator: ", ")
        }
    }

    public var isValid: Bool {
        switch self {
        case .any, .none:
            true
        case .allow(let destinations):
            !destinations.isEmpty
                && destinations.allSatisfy(SSHArgumentPolicy.isValidPermitRemoteOpenDestination)
        }
    }
}

extension ReverseSOCKSPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case destinations
    }

    private enum Kind: String, Codable {
        case any
        case none
        case allow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .any:
            self = .any
        case .none:
            self = .none
        case .allow:
            self = .allow(try container.decode([String].self, forKey: .destinations))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            try container.encode(Kind.any, forKey: .kind)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .allow(let destinations):
            try container.encode(Kind.allow, forKey: .kind)
            try container.encode(destinations, forKey: .destinations)
        }
    }
}

public struct StreamLocalSettings: Codable, Equatable, Sendable {
    public var bindMask: UInt16
    public var unlinkStaleSocket: Bool

    public init(bindMask: UInt16 = 0o177, unlinkStaleSocket: Bool = false) {
        self.bindMask = bindMask
        self.unlinkStaleSocket = unlinkStaleSocket
    }

    public var bindMaskArgument: String {
        String(format: "%04o", bindMask)
    }

    public var isValid: Bool {
        bindMask <= 0o777
    }
}

public enum TunnelGroupTag {
    public static let maximumCharacterCount = 32

    public enum Validation: Equatable {
        case ungrouped
        case valid(String)
        case invalid(String)

        var normalizedName: String? {
            guard case .valid(let name) = self else { return nil }
            return name
        }

        var errorMessage: String? {
            guard case .invalid(let message) = self else { return nil }
            return message
        }
    }

    public static func validate(_ rawValue: String) -> Validation {
        if rawValue.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
                || CharacterSet.newlines.contains($0)
        }) {
            return .invalid(
                "Group names cannot contain line breaks or control characters."
            )
        }

        let normalized = rawValue
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return .ungrouped }
        guard normalized.count <= maximumCharacterCount else {
            return .invalid(
                "Group names can contain at most \(maximumCharacterCount) characters."
            )
        }
        return .valid(normalized)
    }

    public static func resolve(
        _ rawValue: String,
        existingNames: [String]
    ) -> Validation {
        let validation = validate(rawValue)
        guard case .valid(let normalized) = validation else {
            return validation
        }
        let key = canonicalKey(normalized)
        if let existing = existingNames.first(where: { canonicalKey($0) == key }) {
            return .valid(existing)
        }
        return .valid(normalized)
    }

    public static func canonicalKey(_ normalizedName: String) -> String {
        normalizedName.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    public static func isValidStoredValue(_ value: String?) -> Bool {
        guard let value else { return true }
        return validate(value) == .valid(value)
    }
}

public struct Tunnel: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var sshHost: String
    public var additionalArguments: [String]
    public var rules: [ForwardingRule]
    public var reverseSOCKSPolicy: ReverseSOCKSPolicy?
    public var streamLocalSettings: StreamLocalSettings
    public var groupTag: String?
    public var startsAtLaunch: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        sshHost: String,
        additionalArguments: [String] = [],
        rules: [ForwardingRule],
        reverseSOCKSPolicy: ReverseSOCKSPolicy? = nil,
        streamLocalSettings: StreamLocalSettings = StreamLocalSettings(),
        groupTag: String? = nil,
        startsAtLaunch: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sshHost = sshHost
        self.additionalArguments = additionalArguments
        self.rules = rules
        self.reverseSOCKSPolicy = reverseSOCKSPolicy
        self.streamLocalSettings = streamLocalSettings
        self.groupTag = groupTag
        self.startsAtLaunch = startsAtLaunch
    }

    public init(
        id: UUID = UUID(),
        name: String,
        localPort: Int,
        destinationHost: String,
        destinationPort: Int,
        sshHost: String,
        bindAddress: String? = nil,
        additionalArguments: [String] = [],
        groupTag: String? = nil,
        startsAtLaunch: Bool = false
    ) {
        self.init(
            id: id,
            name: name,
            sshHost: sshHost,
            additionalArguments: additionalArguments,
            rules: [
                .localTCP(
                    bindAddress: bindAddress,
                    port: localPort,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            ],
            groupTag: groupTag,
            startsAtLaunch: startsAtLaunch
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sshHost
        case additionalArguments
        case rules
        case reverseSOCKSPolicy
        case streamLocalSettings
        case groupTag
        case startsAtLaunch
        case localPort
        case destinationHost
        case destinationPort
        case bindAddress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sshHost = try container.decode(String.self, forKey: .sshHost)
        additionalArguments = try container.decodeIfPresent(
            [String].self,
            forKey: .additionalArguments
        ) ?? []
        if let decodedGroup = try container.decodeIfPresent(
            String.self,
            forKey: .groupTag
        ) {
            switch TunnelGroupTag.validate(decodedGroup) {
            case .ungrouped:
                groupTag = nil
            case .valid(let normalized):
                groupTag = normalized
            case .invalid(let message):
                throw DecodingError.dataCorruptedError(
                    forKey: .groupTag,
                    in: container,
                    debugDescription: message
                )
            }
        } else {
            groupTag = nil
        }

        startsAtLaunch = try container.decodeIfPresent(
            Bool.self,
            forKey: .startsAtLaunch
        ) ?? false

        if let decodedRules = try container.decodeIfPresent(
            [ForwardingRule].self,
            forKey: .rules
        ) {
            rules = decodedRules
            reverseSOCKSPolicy = try container.decodeIfPresent(
                ReverseSOCKSPolicy.self,
                forKey: .reverseSOCKSPolicy
            )
            streamLocalSettings = try container.decodeIfPresent(
                StreamLocalSettings.self,
                forKey: .streamLocalSettings
            ) ?? StreamLocalSettings()
        } else {
            let localPort = try container.decode(Int.self, forKey: .localPort)
            let destinationHost = try container.decode(String.self, forKey: .destinationHost)
            let destinationPort = try container.decode(Int.self, forKey: .destinationPort)
            let bindAddress = try container.decodeIfPresent(String.self, forKey: .bindAddress)
            rules = [
                .localTCP(
                    bindAddress: bindAddress,
                    port: localPort,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            ]
            reverseSOCKSPolicy = nil
            streamLocalSettings = StreamLocalSettings()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sshHost, forKey: .sshHost)
        try container.encode(additionalArguments, forKey: .additionalArguments)
        try container.encode(rules, forKey: .rules)
        try container.encodeIfPresent(reverseSOCKSPolicy, forKey: .reverseSOCKSPolicy)
        try container.encode(streamLocalSettings, forKey: .streamLocalSettings)
        try container.encodeIfPresent(groupTag, forKey: .groupTag)
        try container.encode(startsAtLaunch, forKey: .startsAtLaunch)
    }

    public var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? (rules.first?.displaySummary ?? sshHost) : trimmedName
    }

    public var displaySummary: String {
        if rules.count == 1 {
            return singleRuleSummary(rules[0], runtimePort: nil)
        }
        return "\(rules.count) forwarding rules via \(sshHost)"
    }

    public func displaySummary(runtimePorts: [UUID: Int]) -> String {
        if rules.count == 1, let rule = rules.first {
            return singleRuleSummary(rule, runtimePort: runtimePorts[rule.id])
        }
        return "\(rules.count) forwarding rules via \(sshHost)"
    }

    private func singleRuleSummary(
        _ rule: ForwardingRule,
        runtimePort: Int?
    ) -> String {
        let summary = rule.displaySummary(runtimePort: runtimePort)
        guard rule.kind == .remoteDynamic, let reverseSOCKSPolicy else {
            return summary
        }
        return "\(summary) · \(reverseSOCKSPolicy.displayText)"
    }

    public var unambiguousBrowserURL: URL? {
        guard rules.count == 1 else { return nil }
        return rules[0].localBrowserURL
    }

    public var exposesBeyondLoopback: Bool {
        rules.contains { rule in
            rule.listen.tcp?.exposesBeyondLoopback == true
        }
    }

    public var hasReverseSOCKS: Bool {
        rules.contains { $0.kind == .remoteDynamic }
    }

    public var createdLocalSocketPaths: [String] {
        rules.compactMap(\.createdLocalSocketPath)
    }

    public var isSafeToRun: Bool {
        guard
            !rules.isEmpty,
            Set(rules.map(\.id)).count == rules.count,
            rules.allSatisfy(\.isValid),
            streamLocalSettings.isValid,
            TunnelGroupTag.isValidStoredValue(groupTag),
            SSHArgumentPolicy.isValidHostTarget(sshHost),
            SSHArgumentPolicy.areAdditionalArgumentsSafe(additionalArguments),
            !hasConflictingListeners
        else {
            return false
        }

        if hasReverseSOCKS {
            guard let reverseSOCKSPolicy, reverseSOCKSPolicy.isValid else { return false }
        }
        return true
    }

    public func hasSameNonTagFields(as other: Tunnel) -> Bool {
        id == other.id
            && name == other.name
            && sshHost == other.sshHost
            && additionalArguments == other.additionalArguments
            && rules == other.rules
            && reverseSOCKSPolicy == other.reverseSOCKSPolicy
            && streamLocalSettings == other.streamLocalSettings
            && startsAtLaunch == other.startsAtLaunch
    }

    public var hasConflictingListeners: Bool {
        for firstIndex in rules.indices {
            for secondIndex in rules.indices where secondIndex > firstIndex {
                let first = rules[firstIndex]
                let second = rules[secondIndex]
                guard first.kind.listensRemotely == second.kind.listensRemotely else {
                    continue
                }
                if SSHForwardingFormat.listenersOverlap(first.listen, second.listen) {
                    return true
                }
            }
        }
        return false
    }

    /// Used by `RemoteServer` to recognize a saved name that merely repeats the
    /// generated endpoint text. The rest of the former compatibility accessors
    /// were removed once Remote Files moved to `RemoteServer`; the legacy
    /// `CodingKeys` that decode v1 records are unaffected.
    public var destinationEndpoint: String {
        rules.first?.destination?.displayText ?? rules.first?.kind.label ?? ""
    }
}

public struct TunnelGroupSection: Identifiable, Equatable {
    public enum ID: Hashable {
        case named(String)
        case ungrouped
    }

    public let id: ID
    public let name: String?
    public let tunnels: [Tunnel]

    public var displayName: String {
        name ?? "Ungrouped"
    }
}

public struct TunnelGrouping: Equatable {
    public let sections: [TunnelGroupSection]
    public let isGrouped: Bool

    public init(tunnels: [Tunnel]) {
        var namedBuckets: [String: (name: String, tunnels: [Tunnel])] = [:]
        var ungrouped: [Tunnel] = []

        for tunnel in tunnels {
            guard
                let rawGroupTag = tunnel.groupTag,
                case .valid(let groupTag) = TunnelGroupTag.validate(rawGroupTag)
            else {
                ungrouped.append(tunnel)
                continue
            }
            let key = TunnelGroupTag.canonicalKey(groupTag)
            if namedBuckets[key] == nil {
                namedBuckets[key] = (groupTag, [])
            }
            namedBuckets[key]?.tunnels.append(tunnel)
        }

        let namedSections = namedBuckets
            .map { key, bucket in
                TunnelGroupSection(
                    id: .named(key),
                    name: bucket.name,
                    tunnels: bucket.tunnels
                )
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName)
                    == .orderedAscending
            }

        isGrouped = !namedSections.isEmpty
        if isGrouped, !ungrouped.isEmpty {
            sections = namedSections + [
                TunnelGroupSection(
                    id: .ungrouped,
                    name: nil,
                    tunnels: ungrouped
                )
            ]
        } else if isGrouped {
            sections = namedSections
        } else {
            sections = [
                TunnelGroupSection(
                    id: .ungrouped,
                    name: nil,
                    tunnels: ungrouped
                )
            ]
        }
    }

    public var groupNames: [String] {
        sections.compactMap(\.name)
    }
}

public enum SSHForwardingFormat {
    public static func unbracket(_ value: String) -> String {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return value }
        return String(value.dropFirst().dropLast())
    }

    public static func bracketIPv6(_ value: String) -> String {
        let unbracketed = unbracket(value)
        return unbracketed.contains(":") ? "[\(unbracketed)]" : unbracketed
    }

    public static func listenersOverlap(
        _ first: ForwardListenEndpoint,
        _ second: ForwardListenEndpoint
    ) -> Bool {
        guard first.kind == second.kind else { return false }
        switch first.kind {
        case .unix:
            return first.path == second.path
        case .tcp:
            guard
                let firstTCP = first.tcp,
                let secondTCP = second.tcp,
                firstTCP.port == secondTCP.port
            else {
                return false
            }
            if firstTCP.port == 0 { return false }
            return bindAddressesOverlap(firstTCP.bindAddress, secondTCP.bindAddress)
        }
    }

    private static func bindAddressesOverlap(_ first: String?, _ second: String?) -> Bool {
        let first = normalizedBind(first)
        let second = normalizedBind(second)
        if first == "any" || second == "any" { return true }
        if first == "loopback" && second == "loopback" { return true }
        return first == second
    }

    private static func normalizedBind(_ bindAddress: String?) -> String {
        guard let bindAddress else { return "any" }
        let value = unbracket(bindAddress)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["", "*", "0.0.0.0", "::"].contains(value) {
            return "any"
        }
        if ["localhost", "127.0.0.1", "::1"].contains(value) {
            return "loopback"
        }
        return value
    }
}

public enum TunnelPhase: Equatable, Sendable {
    case stopped
    case starting
    case retrying(attempt: Int, maxAttempts: Int, delay: TimeInterval, message: String)
    case running
    case failed(String)

    /// Whether the profile currently owns lifecycle work. Group batch actions
    /// and per-row controls agree on this one definition of "active".
    public var isLifecycleActive: Bool {
        switch self {
        case .starting, .retrying, .running: true
        case .stopped, .failed: false
        }
    }
}
