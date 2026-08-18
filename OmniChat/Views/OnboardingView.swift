import SwiftUI

/// Shown once, on first launch, before the empty main window — the same
/// connection setup as Réglages, but with "Ouvrir OmniChat" as the exit.
struct OnboardingView: View {
    let onFinish: () -> Void

    var body: some View {
        ConnectionSetupView(context: .onboarding, onOpenOmniChat: onFinish)
            .padding(36)
            .frame(width: 460)
            .background(OmniTheme.paper)
            .background { OmniPaperTexture() }
    }
}
