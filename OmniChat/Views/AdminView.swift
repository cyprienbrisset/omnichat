import SwiftUI
import OmniRouteKit

/// Real configuration of the connected OmniRoute instance itself, via the
/// management API — not just reading OmniRoute's data (like Memory/MCP),
/// but changing it. Gated on management scope like the rest of this app's
/// `/api/*` features. Built directly in response to this app's own root
/// cause for repeated 404s elsewhere: most of a server's model catalog can
/// belong to providers with no credentials configured at all — this is
/// where that actually gets fixed, from inside OmniChat.
struct AdminView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var section: Section = .providers

    private enum Section: String, CaseIterable, Identifiable {
        case providers, budget, quotas
        var id: String { rawValue }
        var label: String {
            switch self {
            case .providers: "Fournisseurs"
            case .budget: "Budget"
            case .quotas: "Limites & quotas"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            sectionPicker
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            switch section {
            case .providers: ProvidersSectionView()
            case .budget: BudgetSectionView()
            case .quotas: QuotasSectionView()
            }
        }
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("Administration")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
            Text("Administration")
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            Text("Configure directement ton instance OmniRoute via l'API de gestion.")
                .font(OmniTheme.serif(12).italic())
                .foregroundStyle(OmniTheme.inkSoft)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionPicker: some View {
        HStack(spacing: 14) {
            ForEach(Section.allCases) { candidate in
                Button {
                    section = candidate
                } label: {
                    Text(candidate.label.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(section == candidate ? OmniTheme.accent : OmniTheme.inkSoft)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(section == candidate ? OmniTheme.accent : OmniTheme.hairline).frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

// MARK: - Shared raw-field rendering (undocumented shapes)

/// Every raw key/value pair a management-API resource returned, sorted for
/// stable display — the honest fallback whenever a shape isn't documented.
private struct RawFieldRows: View {
    let entries: [(key: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries, id: \.key) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.key)
                        .font(OmniTheme.mono(9, weight: .semibold))
                        .foregroundStyle(OmniTheme.inkSoft)
                        .frame(width: 130, alignment: .leading)
                    Text(entry.value)
                        .font(OmniTheme.mono(10))
                        .foregroundStyle(OmniTheme.ink)
                }
            }
        }
    }
}

/// Folds the fields a card already surfaced prominently out of the raw
/// dump — expandable on demand, same "Afficher tout" pattern used for long
/// tool results in the chat thread, rather than a permanent wall of text.
private struct CollapsibleRawFields: View {
    let collapsedLabel: String
    let entries: [(key: String, value: String)]
    @State private var isExpanded = false

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button(isExpanded ? "Masquer les détails bruts" : collapsedLabel) {
                    isExpanded.toggle()
                }
                .buttonStyle(.omniLink)
                if isExpanded {
                    RawFieldRows(entries: entries)
                }
            }
        }
    }
}

// MARK: - Providers

/// The handful of concepts almost any provider row is likely to carry
/// (name, provider type, status, rate-limit lockout), pulled out of the raw
/// snapshot under several candidate key names — everything else stays in
/// the raw, collapsible fallback rather than being guessed at.
private struct ProviderDisplayFields {
    let name: String?
    let providerType: String?
    let status: String?
    let rateLimitedUntil: String?
    let remainingFields: [(key: String, value: String)]

    private static let knownKeys: Set<String> = [
        "name", "label", "provider", "type", "providerType", "status", "enabled",
        "rateLimitedUntil", "id", "providerId", "_id", "slug",
    ]

    init(_ snapshot: AdminRawSnapshot) {
        func firstString(_ keys: [String]) -> String? {
            for key in keys {
                if case .string(let value)? = snapshot.fields[key] { return value }
            }
            return nil
        }
        name = firstString(["name", "label"])
        providerType = firstString(["provider", "type", "providerType"])
        status = firstString(["status"]) ?? snapshot.fields["enabled"].map(\.displayValue)
        rateLimitedUntil = firstString(["rateLimitedUntil"])
        remainingFields = snapshot.sortedEntries.filter { !Self.knownKeys.contains($0.key) }
    }
}

private struct ProvidersSectionView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var providers: [AdminRawSnapshot] = []
    @State private var loadState: LoadState = .loading
    @State private var showingAddForm = false
    @State private var pendingDeletion: AdminRawSnapshot?
    @State private var actionError: String?
    @State private var testResultsByID: [String: String] = [:]

    private enum LoadState: Equatable {
        case loading, loaded, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("La forme exacte de /api/providers n'est pas documentée — les champs reconnus (nom, type, statut) sont mis en avant, le reste reste consultable en détail.")
                    .font(OmniTheme.serif(11).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
                Spacer()
                Button("+ Ajouter un fournisseur") { showingAddForm = true }
                    .buttonStyle(.omniLink)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if let actionError {
                Text(actionError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            content
        }
        .task { await load() }
        .sheet(isPresented: $showingAddForm) {
            AddProviderSheet { name, type, apiKey in
                await addProvider(name: name, type: type, apiKey: apiKey)
            }
        }
        .alert(
            "Supprimer ce fournisseur ?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { provider in
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { Task { await delete(provider) } }
        } message: { provider in
            Text("Ceci supprime réellement le fournisseur « \(provider.id) » et ses identifiants sur ton serveur OmniRoute.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            centeredMessage("Chargement…")
        case .failed(let message):
            centeredMessage(message)
        case .loaded:
            if providers.isEmpty {
                centeredMessage("Aucun fournisseur retourné par /api/providers.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(providers) { provider in
                            providerRow(provider)
                            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func centeredMessage(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active", "true", "enabled", "ok", "healthy": return OmniTheme.success
        case "false", "disabled", "inactive": return OmniTheme.inkSoft
        default: return OmniTheme.warning
        }
    }

    private func providerRow(_ provider: AdminRawSnapshot) -> some View {
        let display = ProviderDisplayFields(provider)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(display.name ?? provider.id)
                            .font(OmniTheme.serif(15, weight: .semibold))
                            .foregroundStyle(OmniTheme.ink)
                        if let providerType = display.providerType {
                            OmniTheme.label(providerType, size: 8, color: OmniTheme.accent)
                        }
                    }
                    Text(provider.id)
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                    if let status = display.status {
                        HStack(spacing: 5) {
                            Circle().fill(statusColor(status)).frame(width: 6, height: 6)
                            Text(status)
                                .font(OmniTheme.mono(9))
                                .foregroundStyle(OmniTheme.inkSoft)
                        }
                    }
                    if let rateLimitedUntil = display.rateLimitedUntil {
                        Text("Limité (rate limit) jusqu'à \(rateLimitedUntil)")
                            .font(OmniTheme.mono(9))
                            .foregroundStyle(OmniTheme.warning)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Tester") { Task { await test(provider) } }
                        .buttonStyle(.omniLink)
                    Button("Supprimer") { pendingDeletion = provider }
                        .buttonStyle(.omniLink)
                }
            }
            if let result = testResultsByID[provider.id] {
                Text(result)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.accent)
            }
            CollapsibleRawFields(
                collapsedLabel: "Afficher tous les champs (\(display.remainingFields.count))",
                entries: display.remainingFields
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func load() async {
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            providers = try await client.listProviders()
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func test(_ provider: AdminRawSnapshot) async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            let result = try await client.testProvider(id: provider.id)
            testResultsByID[provider.id] = result.sortedEntries.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        } catch let error as OmniRouteError {
            testResultsByID[provider.id] = error.userMessage
        } catch {
            testResultsByID[provider.id] = error.localizedDescription
        }
    }

    private func delete(_ provider: AdminRawSnapshot) async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await client.deleteProvider(id: provider.id)
            providers.removeAll { $0.id == provider.id }
        } catch let error as OmniRouteError {
            actionError = error.userMessage
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func addProvider(name: String, type: String, apiKey: String) async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            let created = try await client.createProvider(name: name, providerType: type, apiKey: apiKey)
            providers.append(created)
            actionError = nil
        } catch let error as OmniRouteError {
            actionError = error.userMessage
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct AddProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, String, String) async -> Void

    @State private var name = ""
    @State private var providerType = ""
    @State private var apiKey = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OmniTheme.label("Nouveau fournisseur", size: 10, color: OmniTheme.accent)
            Text("La forme exacte attendue par /api/providers n'est pas documentée. Si le serveur refuse ces champs, son message d'erreur réel s'affichera ici — pas un message générique.")
                .font(OmniTheme.serif(11).italic())
                .foregroundStyle(OmniTheme.inkSoft)

            labeledField("Nom", text: $name, placeholder: "Mon compte Fireworks")
            labeledField("Identifiant du fournisseur", text: $providerType, placeholder: "fireworks, openai, openrouter…")
            labeledField("Clé API", text: $apiKey, placeholder: "sk-…", isSecure: true)

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .buttonStyle(.omniLink)
                Button(isSubmitting ? "Envoi…" : "Ajouter") {
                    isSubmitting = true
                    Task {
                        await onSubmit(name, providerType, apiKey)
                        isSubmitting = false
                        dismiss()
                    }
                }
                .buttonStyle(.omniLink)
                .disabled(name.isEmpty || providerType.isEmpty || apiKey.isEmpty || isSubmitting)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(OmniTheme.paper)
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label(label, size: 8, color: OmniTheme.inkSoft)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(OmniTheme.mono(12))
            .padding(8)
            .background(OmniTheme.paperMuted)
        }
    }
}

// MARK: - Budget

private struct BudgetSectionView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var budgets: [BudgetEntry] = []
    @State private var loadState: LoadState = .loading
    @State private var apiKeyIDInput = ""
    @State private var dailyInput = ""
    @State private var weeklyInput = ""
    @State private var monthlyInput = ""
    @State private var warningThresholdPercentInput = ""
    @State private var resetInterval = "monthly"
    @State private var setError: String?
    @State private var isSaving = false

    private enum LoadState: Equatable {
        case loading, loaded, failed(String)
    }

    private static let resetIntervals = ["daily", "weekly", "monthly"]

    private var canSave: Bool {
        guard !apiKeyIDInput.isEmpty, !isSaving else { return false }
        return Double(dailyInput) != nil || Double(weeklyInput) != nil || Double(monthlyInput) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { form }
                .frame(maxHeight: 260)
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
        .task { await load() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            OmniTheme.label("Définir un budget", size: 9, color: OmniTheme.inkSoft)
            Text("Trouve l'identifiant de la clé (apiKeyId) dans le tableau de bord OmniRoute. Au moins une des trois limites est requise.")
                .font(OmniTheme.serif(11).italic())
                .foregroundStyle(OmniTheme.inkSoft)

            labeledField("apiKeyId", text: $apiKeyIDInput, width: nil)

            HStack(spacing: 10) {
                labeledField("Jour (USD)", text: $dailyInput, width: 130)
                labeledField("Semaine (USD)", text: $weeklyInput, width: 130)
                labeledField("Mois (USD)", text: $monthlyInput, width: 130)
            }
            HStack(spacing: 10) {
                labeledField("Seuil d'alerte (%)", text: $warningThresholdPercentInput, width: 130)
                VStack(alignment: .leading, spacing: 4) {
                    OmniTheme.label("Réinitialisation", size: 8, color: OmniTheme.inkSoft)
                    Picker("", selection: $resetInterval) {
                        ForEach(Self.resetIntervals, id: \.self) { interval in
                            Text(intervalLabel(interval)).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Spacer()
                Button(isSaving ? "…" : "Enregistrer") { Task { await save() } }
                    .buttonStyle(.omniLink)
                    .disabled(!canSave)
            }
            if let setError {
                Text(setError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func labeledField(_ label: String, text: Binding<String>, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label(label, size: 8, color: OmniTheme.inkSoft)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(OmniTheme.mono(11))
                .padding(8)
                .background(OmniTheme.paperMuted)
                .frame(width: width)
        }
    }

    private func intervalLabel(_ interval: String) -> String {
        switch interval {
        case "daily": "Quotidienne"
        case "weekly": "Hebdomadaire"
        default: "Mensuelle"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            centeredMessage("Chargement…")
        case .failed(let message):
            centeredMessage(message)
        case .loaded:
            if budgets.isEmpty {
                centeredMessage("Aucun budget défini pour l'instant.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(budgets) { budget in
                            budgetRow(budget)
                            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func centeredMessage(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(OmniTheme.serif(13).italic()).foregroundStyle(OmniTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func budgetRow(_ budget: BudgetEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(budget.apiKeyId).font(OmniTheme.mono(10, weight: .semibold)).foregroundStyle(OmniTheme.ink)
            HStack(spacing: 14) {
                if let daily = budget.dailyLimitUsd {
                    Text("Jour : \(String(format: "%.2f $", daily))").font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                }
                if let weekly = budget.weeklyLimitUsd {
                    Text("Semaine : \(String(format: "%.2f $", weekly))").font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                }
                if let monthly = budget.monthlyLimitUsd {
                    Text("Mois : \(String(format: "%.2f $", monthly))").font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                }
                if let warningThreshold = budget.warningThreshold {
                    Text("Alerte à \(Int(warningThreshold * 100))%").font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.warning)
                }
                if let resetInterval = budget.resetInterval {
                    Text(resetInterval).font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            budgets = try await client.listBudgets()
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        setError = nil
        let warningThreshold = Double(warningThresholdPercentInput).map { $0 / 100 }
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await client.setBudget(SetBudgetRequest(
                apiKeyId: apiKeyIDInput,
                dailyLimitUsd: Double(dailyInput),
                weeklyLimitUsd: Double(weeklyInput),
                monthlyLimitUsd: Double(monthlyInput),
                warningThreshold: warningThreshold,
                resetInterval: resetInterval
            ))
            await load()
        } catch let error as OmniRouteError {
            setError = error.userMessage
        } catch {
            setError = error.localizedDescription
        }
    }
}

// MARK: - Quotas (token limits per scope + account rate-limit status)

private enum TokenLimitScope: String, CaseIterable, Identifiable {
    case global, model, provider
    var id: String { rawValue }
    var label: String {
        switch self {
        case .global: "Global"
        case .model: "Modèle"
        case .provider: "Fournisseur"
        }
    }
}

private struct QuotasSectionView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var apiKeyIDInput = ""
    @State private var limits: [TokenLimitEntry] = []
    @State private var loadState: LoadState = .idle
    @State private var scope: TokenLimitScope = .provider
    @State private var scopeValueInput = ""
    @State private var tokenLimitInput = ""
    @State private var setError: String?
    @State private var isSaving = false
    @State private var rateLimitStatus: AdminRawSnapshot?
    @State private var rateLimitError: String?

    private enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private var canSave: Bool {
        guard !apiKeyIDInput.isEmpty, Int(tokenLimitInput) != nil, !isSaving else { return false }
        return scope == .global || !scopeValueInput.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                form
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                limitsContent
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                rateLimitStatusSection
            }
        }
        .task { await loadRateLimitStatus() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            OmniTheme.label("Limites de jetons — quota restant par portée", size: 9, color: OmniTheme.inkSoft)
            Text("Une limite en portée « Fournisseur » est le vrai quota restant par fournisseur pour cette clé — /api/usage/token-limits renvoie tokensUsed/remaining une fois définie.")
                .font(OmniTheme.serif(11).italic())
                .foregroundStyle(OmniTheme.inkSoft)

            HStack(spacing: 10) {
                labeledField("apiKeyId", text: $apiKeyIDInput, width: nil)
                Button("Charger") { Task { await load() } }
                    .buttonStyle(.omniLink)
                    .disabled(apiKeyIDInput.isEmpty)
            }

            Picker("", selection: $scope) {
                ForEach(TokenLimitScope.allCases) { candidate in
                    Text(candidate.label).tag(candidate)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            HStack(spacing: 10) {
                if scope != .global {
                    labeledField(
                        scope == .provider ? "Identifiant du fournisseur" : "Identifiant du modèle",
                        text: $scopeValueInput,
                        width: 220
                    )
                }
                labeledField("Limite (jetons)", text: $tokenLimitInput, width: 140)
                Button(isSaving ? "…" : "Ajouter") { Task { await save() } }
                    .buttonStyle(.omniLink)
                    .disabled(!canSave)
            }
            if let setError {
                Text(setError).font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.danger)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func labeledField(_ label: String, text: Binding<String>, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label(label, size: 8, color: OmniTheme.inkSoft)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(OmniTheme.mono(11))
                .padding(8)
                .background(OmniTheme.paperMuted)
                .frame(width: width)
        }
    }

    @ViewBuilder
    private var limitsContent: some View {
        switch loadState {
        case .idle:
            centeredMessage("Renseigne un apiKeyId puis charge ses limites.", minHeight: 140)
        case .loading:
            centeredMessage("Chargement…", minHeight: 140)
        case .failed(let message):
            centeredMessage(message, minHeight: 140)
        case .loaded:
            if limits.isEmpty {
                centeredMessage("Aucune limite de jetons pour cette clé.", minHeight: 140)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(limits) { limit in
                        limitRow(limit)
                        Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private func centeredMessage(_ text: String, minHeight: CGFloat) -> some View {
        VStack {
            Text(text)
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    private func remainingFraction(_ limit: TokenLimitEntry) -> Double? {
        guard let remaining = limit.remaining, limit.tokenLimit > 0 else { return nil }
        return max(0, min(1, Double(remaining) / Double(limit.tokenLimit)))
    }

    private func progressTint(_ fraction: Double) -> Color {
        if fraction < 0.15 { return OmniTheme.danger }
        if fraction < 0.4 { return OmniTheme.warning }
        return OmniTheme.success
    }

    private func limitRow(_ limit: TokenLimitEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        OmniTheme.label(limit.scopeType, size: 8, color: OmniTheme.accent)
                        if let scopeValue = limit.scopeValue {
                            Text(scopeValue)
                                .font(OmniTheme.mono(11, weight: .semibold))
                                .foregroundStyle(OmniTheme.ink)
                        }
                    }
                    if let remaining = limit.remaining {
                        Text("\(remaining) restants sur \(limit.tokenLimit) jetons" + (limit.resetInterval.map { " · \($0)" } ?? ""))
                            .font(OmniTheme.mono(9))
                            .foregroundStyle(OmniTheme.inkSoft)
                    } else {
                        Text("\(limit.tokensUsed ?? 0) / \(limit.tokenLimit) jetons utilisés" + (limit.resetInterval.map { " · \($0)" } ?? ""))
                            .font(OmniTheme.mono(9))
                            .foregroundStyle(OmniTheme.inkSoft)
                    }
                    if let nextResetAt = limit.nextResetAt {
                        Text("Réinitialisation : \(nextResetAt)")
                            .font(OmniTheme.mono(8))
                            .foregroundStyle(OmniTheme.inkSoft)
                    }
                }
                Spacer()
                Button("Supprimer") { Task { await delete(limit) } }
                    .buttonStyle(.omniLink)
            }
            if let fraction = remainingFraction(limit) {
                ProgressView(value: fraction)
                    .tint(progressTint(fraction))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var rateLimitStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Statut de rate-limit (par compte)", size: 9, color: OmniTheme.inkSoft)
            Text("La forme exacte de /api/rate-limits n'est pas documentée — affiché tel quel.")
                .font(OmniTheme.serif(11).italic())
                .foregroundStyle(OmniTheme.inkSoft)
            if let rateLimitError {
                Text(rateLimitError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
            } else if let rateLimitStatus {
                RawFieldRows(entries: rateLimitStatus.sortedEntries)
            } else {
                Text("Chargement…")
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            limits = try await client.listTokenLimits(apiKeyId: apiKeyIDInput)
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard let tokenLimit = Int(tokenLimitInput) else { return }
        isSaving = true
        defer { isSaving = false }
        setError = nil
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await client.setTokenLimit(SetTokenLimitRequest(
                apiKeyId: apiKeyIDInput,
                scopeType: scope.rawValue,
                scopeValue: scope == .global ? nil : scopeValueInput,
                tokenLimit: tokenLimit
            ))
            await load()
        } catch let error as OmniRouteError {
            setError = error.userMessage
        } catch {
            setError = error.localizedDescription
        }
    }

    private func delete(_ limit: TokenLimitEntry) async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await client.deleteTokenLimit(id: limit.id)
            limits.removeAll { $0.id == limit.id }
        } catch let error as OmniRouteError {
            setError = error.userMessage
        } catch {
            setError = error.localizedDescription
        }
    }

    private func loadRateLimitStatus() async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            rateLimitStatus = try await client.fetchRateLimitStatus()
        } catch let error as OmniRouteError {
            rateLimitError = error.userMessage
        } catch {
            rateLimitError = error.localizedDescription
        }
    }
}
