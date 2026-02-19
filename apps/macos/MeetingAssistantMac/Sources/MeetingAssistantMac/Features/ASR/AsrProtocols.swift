import Foundation

protocol AsrClient: AnyObject {
    var onTranscript: ((TranscriptChunk) -> Void)? { get set }
    func start() async throws
    func sendPcm(_ pcm: [Int16]) async throws
    func stop() async
}

protocol TranslationStream: AnyObject {
    var onTranslation: ((TranslationChunk) -> Void)? { get set }
}

protocol TextTranslator: AnyObject {
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String
}
