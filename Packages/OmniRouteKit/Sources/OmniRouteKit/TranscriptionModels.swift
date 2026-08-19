import Foundation

/// `POST /v1/audio/transcriptions` response — fully documented in the API
/// reference, including a real JSON example, unlike most of the
/// management-API surfaces this package treats defensively.
public struct TranscriptionResult: Decodable, Sendable, Equatable {
    public let text: String
    public let task: String?
    public let language: String?
    public let duration: Double?

    public init(text: String, task: String? = nil, language: String? = nil, duration: Double? = nil) {
        self.text = text
        self.task = task
        self.language = language
        self.duration = duration
    }
}

public protocol AudioTranscribing: Sendable {
    func transcribeAudio(fileData: Data, fileName: String, model: String) async throws -> TranscriptionResult

    /// Real catalog filter — confirmed empirically (like TTS's own
    /// `type`/`subtype` split) that `/v1/models` tags speech-to-text
    /// models `type: "audio", subtype: "transcription"`, distinct from
    /// `subtype: "speech"` (text-to-speech, unusable here).
    func listTranscriptionModels() async throws -> [ModelInfo]
}
