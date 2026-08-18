import Foundation
import SwiftData
import OmniRouteKit

/// A tool OmniChat actually executes itself when the model asks to call it
/// — confirmed real against a live OmniRoute 3.8.49 instance's OpenAI-
/// compatible `tools`/`tool_calls` support on `/v1/chat/completions`. Never
/// a proxy for OmniRoute's embedded MCP server: that surface is `LOCAL_ONLY`
/// (see `OmniRouteClient+MCP.swift`) and unreachable for a self-hosted
/// remote instance, this app's main use case.
protocol LocalTool: Sendable {
    var definition: ToolDefinition { get }
    func execute(argumentsJSON: String) async throws -> String
}

/// Lets the model search whatever local history the user has already
/// indexed via `RAGView` — real passages, real cosine-similarity scores,
/// nothing fabricated when the index is empty.
struct SearchLocalHistoryTool: LocalTool {
    let client: EmbeddingGenerating
    let context: ModelContext

    var definition: ToolDefinition {
        ToolDefinition(function: .init(
            name: "search_local_history",
            description: "Recherche sémantique locale dans l'historique des conversations que l'utilisateur a déjà indexées.",
            parameters: ToolParameterSchema(
                properties: ["query": .init(type: "string", description: "Les mots-clés ou la question à rechercher")],
                required: ["query"]
            )
        ))
    }

    func execute(argumentsJSON: String) async throws -> String {
        struct Arguments: Decodable { let query: String }
        guard let data = argumentsJSON.data(using: .utf8),
              let arguments = try? JSONDecoder().decode(Arguments.self, from: data) else {
            return "Erreur : arguments invalides pour search_local_history."
        }
        guard let embeddingModel = try await client.listEmbeddingModels().first?.id else {
            return "Aucun modèle d'embedding disponible sur ce serveur."
        }
        let results = try await SearchIndexService.search(
            query: arguments.query,
            client: client,
            embeddingModel: embeddingModel,
            context: context,
            limit: 5
        )
        guard !results.isEmpty else {
            return "Aucun résultat local indexé pour cette recherche."
        }
        return results
            .map { "(\(String(format: "%.2f", $0.score))) \($0.passage.text.prefix(200))" }
            .joined(separator: "\n")
    }
}
