import CryptoKit
import Darwin
import Foundation
import Security

public struct OverseerReleaseAsset: Decodable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let digest: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

public struct OverseerRelease: Decodable, Sendable {
    public let tagName: String
    public let name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [OverseerReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, draft, prerelease, assets
    }

    public var isStable: Bool { !draft && !prerelease && tagName.range(of: "^v?[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil }
}

public enum OverseerUpdateError: Error, Equatable {
    case notStable
    case missingAsset
    case checksumMismatch
    case unsignedCandidate
    case wrongIdentity
    case wrongBundle
    case wrongTeam
    case wrongDesignatedRequirement
    case notNotarized
    case replacementFailed
}
private struct PendingUpdateMarker: Codable, Equatable {
    let bundleIdentifier: String
    let shortVersion: String
    let bundleVersion: String
}

public final class OverseerUpdatePreferences: @unchecked Sendable {
    public static let automaticKey = "overseer.updates.install-automatically"
    public static let lastCheckDayKey = "overseer.updates.last-check-day"
    private let defaults: UserDefaults
    private let lockURL: URL

    public init(defaults: UserDefaults = .standard, lockURL: URL? = nil) {
        self.defaults = defaults
        self.lockURL = lockURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("overseer-computer-use-updates.lock")
    }

    public var installAutomatically: Bool {
        get { withLock { defaults.bool(forKey: Self.automaticKey) } }
        set { withLock { defaults.set(newValue, forKey: Self.automaticKey) } }
    }

    public func shouldCheck(on day: String) -> Bool {
        withLock { defaults.string(forKey: Self.lastCheckDayKey) != day }
    }

    public func markChecked(on day: String) {
        withLock { defaults.set(day, forKey: Self.lastCheckDayKey) }
    }

    public func claimCheck(on day: String) -> Bool {
        withLock {
            guard defaults.string(forKey: Self.lastCheckDayKey) != day else { return false }
            defaults.set(day, forKey: Self.lastCheckDayKey)
            return true
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        let fm = FileManager.default
        if !fm.fileExists(atPath: lockURL.path) {
            fm.createFile(atPath: lockURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: lockURL),
              flock(handle.fileDescriptor, LOCK_EX) == 0 else {
            return body()
        }
        defer {
            _ = flock(handle.fileDescriptor, LOCK_UN)
            try? handle.close()
        }
        defaults.synchronize()
        let result = body()
        defaults.synchronize()
        return result
    }
}

public enum OverseerUpdateVerifier {
    public static func sha256(of fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func verifyArchive(
        at archiveURL: URL,
        expectedSHA256: String,
        candidateAppURL: URL,
        bundleIdentifier: String = PermissionSupport.bundleIdentifier,
        teamIdentifier: String = "T63VT9UAY2",
        designatedRequirement: String
    ) throws {
        guard let actual = sha256(of: archiveURL), actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw OverseerUpdateError.checksumMismatch
        }
        try verifyApp(at: candidateAppURL, bundleIdentifier: bundleIdentifier, teamIdentifier: teamIdentifier, designatedRequirement: designatedRequirement)
        guard isNotarized(candidateAppURL) else { throw OverseerUpdateError.notNotarized }
    }

    public static func verifyApp(
        at appURL: URL,
        bundleIdentifier: String = PermissionSupport.bundleIdentifier,
        teamIdentifier: String = "T63VT9UAY2",
        designatedRequirement: String
    ) throws {
        guard let bundle = Bundle(url: appURL), bundle.bundleIdentifier == bundleIdentifier else { throw OverseerUpdateError.wrongBundle }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw OverseerUpdateError.unsignedCandidate
        }
        guard SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw OverseerUpdateError.unsignedCandidate
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any] else { throw OverseerUpdateError.unsignedCandidate }
        guard (info[kSecCodeInfoIdentifier as String] as? String) == bundleIdentifier else { throw OverseerUpdateError.wrongIdentity }
        guard (info[kSecCodeInfoTeamIdentifier as String] as? String) == teamIdentifier else { throw OverseerUpdateError.wrongTeam }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(designatedRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw OverseerUpdateError.wrongDesignatedRequirement
        }
        let authorities = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let firstAuthority = authorities.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? ""
        guard firstAuthority.contains("Developer ID Application") else { throw OverseerUpdateError.wrongIdentity }
    }
    public static func isNotarized(_ appURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["-a", "-vv", "--type", "exec", appURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch { return false }
    }
}

/// Daily stable-release checker. It never installs unless the explicit automatic
/// preference is enabled and the caller supplies a verifier-backed installer.
public final class OverseerUpdater: @unchecked Sendable {
    public static let releasesURL = URL(string: "https://api.github.com/repos/michael-berardi/overseer-computer-use/releases/latest")!
    public static let assetName = "Overseer-Computer-Use.zip"
    private let preferences: OverseerUpdatePreferences
    private let session: URLSession
    private let now: () -> Date
    private var calendar: Calendar

    public init(preferences: OverseerUpdatePreferences = OverseerUpdatePreferences(), session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        self.session = session
        self.now = now
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = utc
    }

    public var installAutomatically: Bool {
        get { preferences.installAutomatically }
        set { preferences.installAutomatically = newValue }
    }

    public func checkLatest(completion: @escaping (Result<OverseerRelease, Error>) -> Void) {
        let day = dayString(now())
        guard preferences.claimCheck(on: day) else { return }
        var request = URLRequest(url: Self.releasesURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Overseer-Computer-Use/\(openComputerUseVersion)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, _, error in
            guard let data, error == nil else {
                completion(.failure(error ?? OverseerUpdateError.missingAsset)); return
            }
            do {
                let release = try JSONDecoder().decode(OverseerRelease.self, from: data)
                guard release.isStable else { throw OverseerUpdateError.notStable }
                guard release.assets.contains(where: { $0.name == Self.assetName }) else { throw OverseerUpdateError.missingAsset }
                completion(.success(release))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    static func pendingUpdateMarkerURL(for bundleURL: URL) -> URL {
        bundleURL.deletingLastPathComponent().appendingPathComponent(".overseer-computer-use-update-pending.json")
    }

    private static func marker(for bundleURL: URL) -> PendingUpdateMarker? {
        guard let bundle = Bundle(url: bundleURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let bundleVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return nil
        }
        return PendingUpdateMarker(bundleIdentifier: bundleIdentifier, shortVersion: shortVersion, bundleVersion: bundleVersion)
    }

    public func installAtomically(
        candidateAppURL: URL,
        currentAppURL: URL,
        archiveURL: URL,
        expectedSHA256: String,
        designatedRequirement: String
    ) throws {
        try OverseerUpdateVerifier.verifyArchive(at: archiveURL, expectedSHA256: expectedSHA256, candidateAppURL: candidateAppURL, designatedRequirement: designatedRequirement)
        let fileManager = FileManager.default
        let lockURL = fileManager.temporaryDirectory.appendingPathComponent("overseer-computer-use-updater.lock")
        if !fileManager.fileExists(atPath: lockURL.path) {
            fileManager.createFile(atPath: lockURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let lockHandle = try? FileHandle(forWritingTo: lockURL),
              flock(lockHandle.fileDescriptor, LOCK_EX) == 0 else {
            throw OverseerUpdateError.replacementFailed
        }
        defer {
            _ = flock(lockHandle.fileDescriptor, LOCK_UN)
            try? lockHandle.close()
        }
        let backupURL = currentAppURL.deletingLastPathComponent().appendingPathComponent(currentAppURL.lastPathComponent + ".previous")
        let markerURL = Self.pendingUpdateMarkerURL(for: currentAppURL)
        guard let pendingMarker = Self.marker(for: candidateAppURL),
              let markerData = try? JSONEncoder().encode(pendingMarker)
        else {
            throw OverseerUpdateError.wrongBundle
        }
        do {
            try markerData.write(to: markerURL, options: .atomic)
            if fileManager.fileExists(atPath: backupURL.path) { try fileManager.removeItem(at: backupURL) }
            try fileManager.moveItem(at: currentAppURL, to: backupURL)
            do {
                try fileManager.moveItem(at: candidateAppURL, to: currentAppURL)
            } catch {
                try? fileManager.moveItem(at: backupURL, to: currentAppURL)
                try? fileManager.removeItem(at: markerURL)
                throw OverseerUpdateError.replacementFailed
            }
        } catch let error as OverseerUpdateError {
            throw error
        } catch {
            try? fileManager.removeItem(at: markerURL)
            throw OverseerUpdateError.replacementFailed
        }
    }

    public static func confirmSuccessfulLaunch(currentBundleURL: URL = Bundle.main.bundleURL) {
        let markerURL = pendingUpdateMarkerURL(for: currentBundleURL)
        guard let markerData = try? Data(contentsOf: markerURL),
              let pendingMarker = try? JSONDecoder().decode(PendingUpdateMarker.self, from: markerData),
              marker(for: currentBundleURL) == pendingMarker
        else {
            return
        }
        let backup = currentBundleURL.deletingLastPathComponent().appendingPathComponent(currentBundleURL.lastPathComponent + ".previous")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.removeItem(at: markerURL)
    }

    public func downloadAndInstall(release: OverseerRelease, automatic: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !automatic || installAutomatically else {
            completion(.failure(OverseerUpdateError.replacementFailed))
            return
        }
        guard let asset = release.assets.first(where: { $0.name == Self.assetName }) else {
            completion(.failure(OverseerUpdateError.missingAsset))
            return
        }
        let checksumAsset = release.assets.first(where: { $0.name == "\(Self.assetName).sha256" })
        let resolveDigest: (@escaping (String?) -> Void) -> Void = { [session] finish in
            if let digest = asset.digest {
                finish(digest)
                return
            }
            guard let checksumAsset else {
                finish(nil)
                return
            }
            session.dataTask(with: checksumAsset.browserDownloadURL) { data, _, _ in
                finish(data.flatMap { String(data: $0, encoding: .utf8) })
            }.resume()
        }
        resolveDigest { digestText in
            guard let digestText else {
                completion(.failure(OverseerUpdateError.missingAsset))
                return
            }
            let expectedSHA = digestText.replacingOccurrences(of: "sha256:", with: "").split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? ""
            guard expectedSHA.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
                completion(.failure(OverseerUpdateError.checksumMismatch))
                return
            }
            self.session.downloadTask(with: asset.browserDownloadURL) { [weak self] temporaryURL, _, error in
                guard let self, let temporaryURL, error == nil else {
                    completion(.failure(error ?? OverseerUpdateError.missingAsset))
                    return
                }
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("overseer-update-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                    let archive = work.appendingPathComponent(Self.assetName)
                    try FileManager.default.moveItem(at: temporaryURL, to: archive)
                    let extract = work.appendingPathComponent("extract", isDirectory: true)
                    try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
                    let ditto = Process()
                    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    ditto.arguments = ["-x", "-k", archive.path, extract.path]
                    try ditto.run()
                    ditto.waitUntilExit()
                    guard ditto.terminationStatus == 0 else { throw OverseerUpdateError.replacementFailed }
                    let candidate = extract.appendingPathComponent("Overseer Computer Use.app")
                    let requirement = "identifier \"\(PermissionSupport.bundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"T63VT9UAY2\""
                    try self.installAtomically(candidateAppURL: candidate, currentAppURL: Bundle.main.bundleURL, archiveURL: archive, expectedSHA256: expectedSHA, designatedRequirement: requirement)
                    try? FileManager.default.removeItem(at: work)
                    completion(.success(()))
                } catch {
                    try? FileManager.default.removeItem(at: work)
                    completion(.failure(error))
                }
            }.resume()
        }
    }
    private func dayString(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
