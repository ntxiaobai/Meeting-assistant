import Foundation

final class ProviderConfigStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> SpeechSettingsEnvelope {
        guard let path = settingsFilePath() else {
            return .init()
        }
        guard fileManager.fileExists(atPath: path.path) else {
            return .init()
        }
        do {
            let data = try Data(contentsOf: path)
            return try decoder.decode(SpeechSettingsEnvelope.self, from: data)
        } catch {
            return .init()
        }
    }

    func save(_ settings: SpeechSettingsEnvelope) throws {
        guard let path = settingsFilePath() else {
            throw NSError(domain: "ProviderConfigStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Application Support directory"])
        }

        if !fileManager.fileExists(atPath: path.deletingLastPathComponent().path) {
            try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let data = try encoder.encode(settings)
        try data.write(to: path, options: .atomic)
    }

    private func settingsFilePath() -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("MeetingAssistantMac", isDirectory: true)
            .appendingPathComponent("speech_pipeline_settings.json")
    }
}
