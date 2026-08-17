import SwiftUI
import OmniRouteKit

struct ErrorBannerView: View {
    let error: OmniRouteError
    let retryAction: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message)
            Spacer()
            Button("Réessayer", action: retryAction)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var message: String {
        switch error {
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
