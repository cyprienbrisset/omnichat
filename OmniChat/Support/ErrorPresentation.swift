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
            return "La réponse a été interrompue avant la fin."
        case .unknown:
            return "Une erreur inattendue est survenue."
        }
    }
}
