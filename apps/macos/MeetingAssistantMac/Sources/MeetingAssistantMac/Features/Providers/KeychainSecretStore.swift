import Foundation
import Security

struct ProviderSecretSnapshot: Codable {
    var deepgramApiKey: String?
    var aliyunAccessKeyId: String?
    var aliyunAccessKeySecret: String?
    var aliyunAppKey: String?
    var microsoftTranslatorKey: String?
    var anthropicApiKey: String?
    var openaiApiKey: String?
    var customLlmApiKey: String?
}

struct ProviderSecretProfileSummary: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var hasDeepgram: Bool
    var hasAliyun: Bool
    var hasMicrosoft: Bool
}

final class KeychainSecretStore {
    struct ProfileCatalog: Codable {
        var activeProfileId: String?
        var profiles: [ProviderSecretProfileSummary]
    }

    private let serviceName = "com.meetingassistant.mac.speech"
    private let legacyUnifiedAccount = "provider.snapshot.v1"
    private let profileAccountPrefix = "provider.snapshot.profile."
    private let catalogFileName = "provider_secret_profiles.v1.json"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var cachedCatalog: ProfileCatalog?
    private var cachedSnapshot: ProviderSecretSnapshot?
    private var cachedSnapshotProfileId: String?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadSnapshot(forceReload: Bool = false) -> ProviderSecretSnapshot {
        guard let profileId = activeProfileId(forceReload: forceReload) else {
            return .init()
        }

        if !forceReload,
           cachedSnapshotProfileId == profileId,
           let cachedSnapshot
        {
            return cachedSnapshot
        }

        let snapshot = loadSnapshot(forProfileId: profileId) ?? .init()
        cachedSnapshotProfileId = profileId
        cachedSnapshot = snapshot
        return snapshot
    }

    func listProfiles(forceReload: Bool = false) -> [ProviderSecretProfileSummary] {
        guard let catalog = ensureCatalog(forceReload: forceReload) else {
            return []
        }
        return catalog.profiles
    }

    func activeProfileId(forceReload: Bool = false) -> String? {
        ensureCatalog(forceReload: forceReload)?.activeProfileId
    }

    func activeProfileName(forceReload: Bool = false) -> String? {
        guard let catalog = ensureCatalog(forceReload: forceReload),
              let activeId = catalog.activeProfileId
        else {
            return nil
        }
        return catalog.profiles.first(where: { $0.id == activeId })?.name
    }

    @discardableResult
    func setActiveProfile(_ profileId: String) -> Bool {
        guard var catalog = ensureCatalog(forceReload: true),
              catalog.profiles.contains(where: { $0.id == profileId })
        else {
            return false
        }

        catalog.activeProfileId = profileId
        guard saveCatalog(catalog) else {
            return false
        }

        cachedSnapshotProfileId = nil
        cachedSnapshot = nil
        return true
    }

    @discardableResult
    func createProfile(name: String) -> ProviderSecretProfileSummary? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        guard var catalog = ensureCatalog(forceReload: true) else {
            return nil
        }

        let now = Date()
        let profile = ProviderSecretProfileSummary(
            id: UUID().uuidString,
            name: trimmedName,
            createdAt: now,
            updatedAt: now,
            hasDeepgram: false,
            hasAliyun: false,
            hasMicrosoft: false
        )

        catalog.profiles.insert(profile, at: 0)
        catalog.activeProfileId = profile.id

        guard saveCatalog(catalog),
              saveSnapshot(.init(), forProfileId: profile.id)
        else {
            return nil
        }

        cachedSnapshotProfileId = profile.id
        cachedSnapshot = .init()
        return profile
    }

    @discardableResult
    func saveDeepgramApiKey(_ value: String) -> Bool {
        var snapshot = loadSnapshot()
        snapshot.deepgramApiKey = value
        return saveSnapshot(snapshot)
    }

    @discardableResult
    func saveAliyun(accessKeyId: String, accessKeySecret: String, appKey: String) -> Bool {
        var snapshot = loadSnapshot()
        snapshot.aliyunAccessKeyId = accessKeyId
        snapshot.aliyunAccessKeySecret = accessKeySecret
        snapshot.aliyunAppKey = appKey
        return saveSnapshot(snapshot)
    }

    @discardableResult
    func saveMicrosoftTranslatorKey(_ value: String) -> Bool {
        var snapshot = loadSnapshot()
        snapshot.microsoftTranslatorKey = value
        return saveSnapshot(snapshot)
    }

    @discardableResult
    func saveSnapshot(_ snapshot: ProviderSecretSnapshot) -> Bool {
        guard var catalog = ensureCatalog(forceReload: true),
              let profileId = catalog.activeProfileId
        else {
            return false
        }

        guard saveSnapshot(snapshot, forProfileId: profileId) else {
            return false
        }

        if let index = catalog.profiles.firstIndex(where: { $0.id == profileId }) {
            var profile = catalog.profiles[index]
            profile.updatedAt = Date()
            profile.hasDeepgram = hasValue(snapshot.deepgramApiKey)
            profile.hasAliyun = hasValue(snapshot.aliyunAccessKeyId) &&
                hasValue(snapshot.aliyunAccessKeySecret) &&
                hasValue(snapshot.aliyunAppKey)
            profile.hasMicrosoft = hasValue(snapshot.microsoftTranslatorKey)
            catalog.profiles[index] = profile
        }

        guard saveCatalog(catalog) else {
            return false
        }

        cachedSnapshotProfileId = profileId
        cachedSnapshot = snapshot
        return true
    }
}

private extension KeychainSecretStore {
    func ensureCatalog(forceReload: Bool = false) -> ProfileCatalog? {
        if !forceReload, let cachedCatalog {
            return cachedCatalog
        }

        if let catalog = loadCatalogFromDisk() {
            let sanitized = sanitizeCatalog(catalog)
            if sanitized.activeProfileId != catalog.activeProfileId || sanitized.profiles != catalog.profiles {
                _ = saveCatalog(sanitized)
            }
            cachedCatalog = sanitized
            return sanitized
        }

        if let migrated = migrateLegacySnapshot() {
            cachedCatalog = migrated
            return migrated
        }

        let created = createDefaultCatalog()
        cachedCatalog = created
        return created
    }

    func sanitizeCatalog(_ catalog: ProfileCatalog) -> ProfileCatalog {
        var next = catalog
        if next.profiles.isEmpty {
            return createDefaultCatalog() ?? ProfileCatalog(activeProfileId: nil, profiles: [])
        }

        if let activeId = next.activeProfileId,
           next.profiles.contains(where: { $0.id == activeId })
        {
            return next
        }

        next.activeProfileId = next.profiles.first?.id
        return next
    }

    func createDefaultCatalog() -> ProfileCatalog? {
        let now = Date()
        let profile = ProviderSecretProfileSummary(
            id: UUID().uuidString,
            name: "Default",
            createdAt: now,
            updatedAt: now,
            hasDeepgram: false,
            hasAliyun: false,
            hasMicrosoft: false
        )
        let catalog = ProfileCatalog(activeProfileId: profile.id, profiles: [profile])
        guard saveCatalog(catalog),
              saveSnapshot(.init(), forProfileId: profile.id)
        else {
            return nil
        }
        return catalog
    }

    func migrateLegacySnapshot() -> ProfileCatalog? {
        guard let data = loadRaw(account: legacyUnifiedAccount),
              let snapshot = try? decoder.decode(ProviderSecretSnapshot.self, from: data)
        else {
            return nil
        }

        let now = Date()
        let profile = ProviderSecretProfileSummary(
            id: UUID().uuidString,
            name: "Migrated Legacy",
            createdAt: now,
            updatedAt: now,
            hasDeepgram: hasValue(snapshot.deepgramApiKey),
            hasAliyun: hasValue(snapshot.aliyunAccessKeyId) &&
                hasValue(snapshot.aliyunAccessKeySecret) &&
                hasValue(snapshot.aliyunAppKey),
            hasMicrosoft: hasValue(snapshot.microsoftTranslatorKey)
        )
        let catalog = ProfileCatalog(activeProfileId: profile.id, profiles: [profile])

        guard saveCatalog(catalog),
              saveSnapshot(snapshot, forProfileId: profile.id)
        else {
            return nil
        }

        cachedSnapshotProfileId = profile.id
        cachedSnapshot = snapshot
        return catalog
    }

    func profileAccount(for profileId: String) -> String {
        "\(profileAccountPrefix)\(profileId)"
    }

    func loadSnapshot(forProfileId profileId: String) -> ProviderSecretSnapshot? {
        guard let data = loadRaw(account: profileAccount(for: profileId)),
              let snapshot = try? decoder.decode(ProviderSecretSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: ProviderSecretSnapshot, forProfileId profileId: String) -> Bool {
        guard let data = try? encoder.encode(snapshot) else {
            return false
        }
        return saveRaw(account: profileAccount(for: profileId), data: data)
    }

    func hasValue(_ value: String?) -> Bool {
        !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func catalogFilePath() -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("MeetingAssistantMac", isDirectory: true)
            .appendingPathComponent(catalogFileName)
    }

    func loadCatalogFromDisk() -> ProfileCatalog? {
        guard let path = catalogFilePath(),
              fileManager.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let catalog = try? decoder.decode(ProfileCatalog.self, from: data)
        else {
            return nil
        }
        return catalog
    }

    func saveCatalog(_ catalog: ProfileCatalog) -> Bool {
        guard let path = catalogFilePath() else {
            return false
        }

        let parent = path.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        guard let data = try? encoder.encode(catalog) else {
            return false
        }

        do {
            try data.write(to: path, options: .atomic)
            cachedCatalog = catalog
            return true
        } catch {
            return false
        }
    }

    func saveRaw(account: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attributes: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func loadRaw(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }
}
