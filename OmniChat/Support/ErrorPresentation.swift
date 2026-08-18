import SwiftUI
import OmniRouteKit

/// French, user-facing phrasing for each `OmniRouteError` case — shared by
/// the chat error banner and the settings connection test so the wording
/// never drifts between the two call sites.
extension OmniRouteError {
    var userMessage: String {
        switch self {
        case .authenticationFailed:
            return "Clé API invalide ou expirée. Vérifie les réglages."
        case .rateLimited(let retryAfter):
            let suffix = retryAfter.map { " Réessaie dans \(Int($0))s." } ?? ""
            return "Limite de requêtes atteinte." + suffix
        case .network:
            return "Impossible de joindre OmniRoute. Vérifie ta connexion ou l'endpoint configuré."
        case .invalidResponse(let statusCode):
            return "Réponse inattendue d'OmniRoute (code \(statusCode))."
        case .streamInterrupted:
            return "La réponse a été interrompue avant la fin. Le fragment reçu est conservé."
        case .unknown(let description):
            // `.unknown` is how this app surfaces specific, real diagnostics
            // it can't classify into the other cases (unrecognized response
            // shapes, server-specific restrictions like MCP's LOCAL_ONLY) —
            // showing a generic string here would discard exactly the detail
            // that makes those messages useful.
            return description
        }
    }

    /// The mockup's per-code error cards use the HTTP status (or a symbolic
    /// stand-in for cases with no single status code) as the visual anchor.
    var codeLabel: String {
        switch self {
        case .authenticationFailed: return "401"
        case .rateLimited: return "429"
        case .network: return "—"
        case .invalidResponse(let statusCode): return "\(statusCode)"
        case .streamInterrupted: return "SSE"
        case .unknown: return "?"
        }
    }

    var codeTitle: String {
        switch self {
        case .authenticationFailed: return "Clé refusée"
        case .rateLimited: return "Quota atteint"
        case .network: return "Serveur injoignable"
        case .invalidResponse: return "Réponse inattendue"
        case .streamInterrupted: return "Flux coupé"
        case .unknown: return "Erreur inconnue"
        }
    }

    var codeColor: Color {
        switch self {
        case .authenticationFailed, .invalidResponse: return OmniTheme.danger
        case .rateLimited: return OmniTheme.warning
        case .network, .streamInterrupted, .unknown: return OmniTheme.inkSoft
        }
    }

    /// The retry button reads differently depending on what actually
    /// resumes — a plain retry vs. picking the streamed response back up.
    var retryActionLabel: String {
        switch self {
        case .streamInterrupted: return "Reprendre la génération"
        default: return "Réessayer"
        }
    }
}
