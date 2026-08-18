import Foundation

public struct MediaGenerationRequest: Encodable, Sendable {
    public var model: String
    public var prompt: String
    public var size: String?

    public init(model: String, prompt: String, size: String? = nil) {
        self.model = model
        self.prompt = prompt
        self.size = size
    }
}

public struct SpeechRequest: Encodable, Sendable {
    public var model: String
    public var input: String
    public var voice: String

    public init(model: String, input: String, voice: String = "alloy") {
        self.model = model
        self.input = input
        self.voice = voice
    }
}

public enum MediaGenerationResult: Sendable, Equatable {
    case remoteURL(URL)
    case inlineData(Data, contentType: String)
}

public protocol MediaGenerating: Sendable {
    func generateImage(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult
    func generateVideo(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult
    func generateMusic(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult
    func synthesizeSpeech(_ request: SpeechRequest) async throws -> MediaGenerationResult

    /// Real per-kind catalogs — confirmed empirically that the media
    /// generation endpoints reject the chat-only `"auto"` routing alias
    /// (`"Invalid image model: auto. Use format: provider/model"`), so
    /// callers must resolve one of these real ids first.
    func listImageModels() async throws -> [ModelInfo]
    func listVideoModels() async throws -> [ModelInfo]
    func listMusicModels() async throws -> [ModelInfo]
    func listSpeechModels() async throws -> [ModelInfo]
}

struct MediaGenerationResponse: Decodable {
    struct DataItem: Decodable {
        let url: String?
        let b64Json: String?

        private enum CodingKeys: String, CodingKey {
            case url
            case b64Json = "b64_json"
        }
    }
    let data: [DataItem]
}

enum MediaResponseParsingError: Error {
    case emptyData
    case unrecognizedItem
}

func parseMediaGenerationResponse(_ data: Data, defaultContentType: String) throws -> MediaGenerationResult {
    let decoded = try JSONDecoder().decode(MediaGenerationResponse.self, from: data)
    guard let first = decoded.data.first else {
        throw MediaResponseParsingError.emptyData
    }
    if let urlString = first.url, let url = URL(string: urlString) {
        return .remoteURL(url)
    }
    if let base64 = first.b64Json, let decodedData = Data(base64Encoded: base64) {
        return .inlineData(decodedData, contentType: defaultContentType)
    }
    throw MediaResponseParsingError.unrecognizedItem
}
