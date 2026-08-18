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
        case providers, budget, tokenLimits
        var id: String { rawValue }
        var label: String {
            switch self {
            case .providers: "Fournisseurs"
            case .budget: "Budget"
            case .tokenLimits: "Limites de jetons"
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
            case .tokenLimits: TokenLimitsSectionView()
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

// MARK: - Providers

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
                Text("La forme exacte de /api/providers n'est pas documentée — cette liste s'affiche telle quelle.")
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

    private func providerRow(_ provider: AdminRawSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.sortedEntries, id: \.key) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.key)
                                .font(OmniTheme.mono(9, weight: .semibold))
                                .foregroundStyle(OmniTheme.inkSoft)
                                .frame(width: 110, alignment: .leading)
                            Text(entry.value)
                                .font(OmniTheme.mono(10))
                                .foregroundStyle(OmniTheme.ink)
                        }
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
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
    @State private var monthlyLimitInput = ""
    @State private var setError: String?
    @State private var isSaving = false

    private enum LoadState: Equatable {
        case loading, loaded, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            form
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
        .task { await load() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Définir un budget", size: 9, color: OmniTheme.inkSoft)
            Text("Trouve l'identifiant de la clé (apiKeyId) dans le tableau de bord OmniRoute.")
                .font(OmniTheme.serif(11).italic())
                .foregroundStyle(OmniTheme.inkSoft)
            HStack(spacing: 10) {
                TextField("apiKeyId", text: $apiKeyIDInput)
                    .textFieldStyle(.plain)
                    .font(OmniTheme.mono(11))
                    .padding(8)
                    .background(OmniTheme.paperMuted)
                TextField("Limite mensuelle (USD)", text: $monthlyLimitInput)
                    .textFieldStyle(.plain)
                    .font(OmniTheme.mono(11))
                    .padding(8)
                    .background(OmniTheme.paperMuted)
                    .frame(width: 160)
                Button(isSaving ? "…" : "Enregistrer") { Task { await save() } }
                    .buttonStyle(.omniLink)
                    .disabled(apiKeyIDInput.isEmpty || Double(monthlyLimitInput) == nil || isSaving)
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
        guard let monthly = Double(monthlyLimitInput) else { return }
        isSaving = true
        defer { isSaving = false }
        setError = nil
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await client.setBudget(SetBudgetRequest(apiKeyId: apiKeyIDInput, monthlyLimitUsd: monthly, resetInterval: "monthly"))
            await load()
        } catch let error as OmniRouteError {
            setError = error.userMessage
        } catch {
            setError = error.localizedDescription
        }
    }
}

// MARK: - Token limits

private struct TokenLimitsSectionView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var apiKeyIDInput = ""
    @State private var limits: [TokenLimitEntry] = []
    @State private var loadState: LoadState = .idle
    @State private var scopeValueInput = ""
    @State private var tokenLimitInput = ""
    @State private var setError: String?
    @State private var isSaving = false

    private enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            form
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Limites de jetons par clé", size: 9, color: OmniTheme.inkSoft)
            HStack(spacing: 10) {
                TextField("apiKeyId", text: $apiKeyIDInput)
                    .textFieldStyle(.plain)
                    .font(OmniTheme.mono(11))
                    .padding(8)
                    .background(OmniTheme.paperMuted)
                Button("Charger") { Task { await load() } }
                    .buttonStyle(.omniLink)
                    .disabled(apiKeyIDInput.isEmpty)
            }
            HStack(spacing: 10) {
                TextField("Portée (global, ou id de modèle/fournisseur)", text: $scopeValueInput)
                    .textFieldStyle(.plain)
                    .font(OmniTheme.mono(11))
                    .padding(8)
                    .background(OmniTheme.paperMuted)
                TextField("Limite (jetons)", text: $tokenLimitInput)
                    .textFieldStyle(.plain)
                    .font(OmniTheme.mono(11))
                    .padding(8)
                    .background(OmniTheme.paperMuted)
                    .frame(width: 140)
                Button(isSaving ? "…" : "Ajouter") { Task { await save() } }
                    .buttonStyle(.omniLink)
                    .disabled(apiKeyIDInput.isEmpty || Int(tokenLimitInput) == nil || isSaving)
            }
            if let setError {
                Text(setError).font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.danger)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle:
            centeredMessage("Renseigne un apiKeyId puis charge ses limites.")
        case .loading:
            centeredMessage("Chargement…")
        case .failed(let message):
            centeredMessage(message)
        case .loaded:
            if limits.isEmpty {
                centeredMessage("Aucune limite de jetons pour cette clé.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(limits) { limit in
                            limitRow(limit)
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
            Text(text).font(OmniTheme.serif(13).italic()).foregroundStyle(OmniTheme.inkSoft).multilineTextAlignment(.center).frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func limitRow(_ limit: TokenLimitEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(limit.scopeType)\(limit.scopeValue.map { " · \($0)" } ?? "")")
                    .font(OmniTheme.mono(10, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
                Text("\(limit.tokensUsed ?? 0) / \(limit.tokenLimit) jetons" + (limit.resetInterval.map { " · \($0)" } ?? ""))
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            Spacer()
            Button("Supprimer") { Task { await delete(limit) } }
                .buttonStyle(.omniLink)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
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
        let scopeType = scopeValueInput.isEmpty || scopeValueInput.lowercased() == "global" ? "global" : "model"
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await client.setTokenLimit(SetTokenLimitRequest(
                apiKeyId: apiKeyIDInput,
                scopeType: scopeType,
                scopeValue: scopeType == "global" ? nil : scopeValueInput,
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
}
