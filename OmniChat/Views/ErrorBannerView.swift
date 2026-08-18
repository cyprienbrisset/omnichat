import SwiftUI
import OmniRouteKit

struct ErrorBannerView: View {
    let error: OmniRouteError
    let retryAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
            Spacer()
            Button("Réessayer", action: retryAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
