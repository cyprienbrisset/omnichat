import SwiftUI
import SwiftData
import OmniRouteKit

/// The connection screen — shared between first-launch onboarding and the
/// regular Réglages window, matching the mockup's copy and layout exactly.
/// Every number it shows is either static product copy (OmniRoute's own
/// provider count) or measured live against the configured server; nothing
/// here is a placeholder pretending to be real data.
struct ConnectionSetupView: View {
    enum Context {
        case onboarding
        case settings
    }

    let context: Context
    var onOpenOmniChat: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @State private var baseURLText = ""
    @State private var apiKey = ""
    @State private var saveError: String?
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case testing
        case success(report: ServerReport)
        case failure(String)
    }

    struct ServerReport: Equatable {
        let modelCount: Int
        let providerCount: Int
        let latencyMs: Int
    }

    var body: some View {
        VStack(spacing: 26) {
            header

            VStack(alignment: .leading, spacing: 16) {
                endpointField
                apiKeyField
                if case .success(let report) = testState {
                    serverReportBox(report)
                }
            }

            if let saveError {
                Text(saveError)
                    .font(OmniTheme.mono(11))
                    .foregroundStyle(OmniTheme.danger)
            }

            footer
        }
        .onAppear {
            baseURLText = appEnvironment.activeProfile.baseURL.absoluteString
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("O")
                .font(OmniTheme.serif(20, weight: .bold))
                .foregroundStyle(OmniTheme.ink)
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(OmniTheme.ink, lineWidth: 1))

            OmniTheme.label("OmniChat pour macOS", size: 9, color: OmniTheme.inkSoft)

            Text("Une passerelle,\ntrois cent quarante\nfournisseurs.")
                .font(OmniTheme.serif(30, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(OmniTheme.ink)
                .lineSpacing(2)

            Rectangle().fill(OmniTheme.ink.opacity(0.4)).frame(width: 64, height: 1)

            Text("Indique où tourne ton serveur OmniRoute. La clé est rangée dans le trousseau macOS, hors iCloud.")
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    private var endpointField: some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Endpoint", size: 8, color: OmniTheme.inkSoft)
            HStack(spacing: 10) {
                TextField("https://omniroute.online/v1", text: $baseURLText)
                    .textFieldStyle(.plain)
                    .font(OmniTheme.mono(13))
                    .foregroundStyle(OmniTheme.ink)
                Spacer(minLength: 8)
                testStatusLabel
            }
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(OmniTheme.ink).frame(height: 1)
            }

            HStack(spacing: 4) {
                Text("profil « \(appEnvironment.activeProfile.name.isEmpty ? "défaut" : appEnvironment.activeProfile.name.lowercased()) » · ou")
                Button("http://localhost:20128/v1") {
                    baseURLText = "http://localhost:20128/v1"
                }
                .buttonStyle(.plain)
                .foregroundStyle(OmniTheme.accent)
            }
            .font(OmniTheme.mono(9))
            .foregroundStyle(OmniTheme.inkSoft)
        }
    }

    @ViewBuilder
    private var testStatusLabel: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            Text("Test en cours…")
                .font(OmniTheme.mono(9, weight: .bold))
                .foregroundStyle(OmniTheme.inkSoft)
        case .success(let report):
            Text("Joignable · \(report.latencyMs) ms")
                .font(OmniTheme.mono(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(OmniTheme.success)
        case .failure(let message):
            Text(message)
                .font(OmniTheme.mono(9, weight: .bold))
                .foregroundStyle(OmniTheme.danger)
                .lineLimit(1)
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Clé du tableau de bord", size: 8, color: OmniTheme.inkSoft)
            HStack(spacing: 10) {
                SecureField(
                    "",
                    text: $apiKey,
                    prompt: Text(maskedExistingKeyHint)
                        .font(OmniTheme.mono(13))
                        .foregroundStyle(OmniTheme.inkSoft)
                )
                .textFieldStyle(.plain)
                .font(OmniTheme.mono(13))
                .foregroundStyle(OmniTheme.ink)
                Spacer(minLength: 8)
                Button("Coller", action: pasteFromClipboard)
                    .buttonStyle(.omniLink)
            }
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            }

            Text("trousseau à protection de données · jamais synchronisée")
                .font(OmniTheme.mono(9))
                .foregroundStyle(OmniTheme.inkSoft)
        }
    }

    private var maskedExistingKeyHint: String {
        guard let key = try? appEnvironment.credentialStore.apiKey(for: appEnvironment.activeProfile.id),
              key.count > 4 else {
            return "Coller ta clé API…"
        }
        return String(repeating: "•", count: min(key.count - 4, 14)) + key.suffix(4)
    }

    private func serverReportBox(_ report: ServerReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OmniTheme.label("Relevé du serveur", size: 8, color: OmniTheme.inkSoft)
            HStack(spacing: 0) {
                reportStat(value: "\(report.modelCount)", label: "Modèles")
                Spacer()
                reportStat(value: "\(report.providerCount)", label: "Fournisseurs")
                Spacer()
                reportStat(value: "\(report.latencyMs) ms", label: "Latence")
            }
        }
        .padding(14)
        .background(OmniTheme.paperMuted)
        .overlay(RoundedRectangle(cornerRadius: 0).stroke(OmniTheme.hairline, lineWidth: 1))
    }

    private func reportStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(OmniTheme.serif(18, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            OmniTheme.label(label, size: 9, color: OmniTheme.inkSoft)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Tester encore") {
                guard performSave() else { return }
                Task { await runConnectionTest() }
            }
            .buttonStyle(.omniLink)

            Spacer()

            Button(context == .onboarding ? "Ouvrir OmniChat" : "Enregistrer") {
                guard performSave() else { return }
                Task { await runConnectionTest() }
                onOpenOmniChat?()
            }
            .buttonStyle(.omniPrimary)
        }
    }

    private func pasteFromClipboard() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            apiKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Validates and persists the current fields. Returns whether it
    /// succeeded, so callers can decide whether to proceed (run a test,
    /// dismiss onboarding) or stop and let the error message show.
    @discardableResult
    private func performSave() -> Bool {
        guard let url = URL(string: baseURLText),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            saveError = "URL invalide"
            return false
        }
        do {
            try appEnvironment.persistActiveProfile(baseURL: url, apiKey: apiKey, context: modelContext)
            saveError = nil
            apiKey = ""
            Task { await appEnvironment.refreshManagementAccess() }
            return true
        } catch {
            saveError = "Impossible d'enregistrer la clé : \(error.localizedDescription)"
            return false
        }
    }

    private func runConnectionTest() async {
        testState = .testing
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        let started = Date()
        do {
            let models = try await client.listModels()
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            let providerCount = Set(models.compactMap(\.ownedBy)).count
            testState = .success(report: ServerReport(modelCount: models.count, providerCount: providerCount, latencyMs: elapsedMs))
            appEnvironment.updateCatalogSummary(modelCount: models.count, providerCount: providerCount)
        } catch let error as OmniRouteError {
            testState = .failure(error.userMessage)
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}
