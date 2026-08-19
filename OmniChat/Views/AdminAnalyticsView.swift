import SwiftUI
import OmniRouteKit

/// Analytique & coûts (mockup 4b) — the mockup doesn't split this into
/// sub-tabs, but three genuinely different real resources feed it (budget
/// limits, token quotas, latency/success-rate analytics), so this keeps
/// them as an internal picker rather than one impossibly long page.
struct AdminAnalyticsView: View {
    @State private var tab: Tab = .budget

    private enum Tab: String, CaseIterable, Identifiable {
        case budget, quotas, latency
        var id: String { rawValue }
        var label: String {
            switch self {
            case .budget: "Budget"
            case .quotas: "Limites & quotas"
            case .latency: "Latence & succès"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            tabPicker
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            switch tab {
            case .budget: BudgetSectionView()
            case .quotas: QuotasSectionView()
            case .latency: LatencyStatsSectionView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Contrôle", size: 10, color: OmniTheme.inkSoft)
            Text("Analytique & coûts")
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabPicker: some View {
        HStack(spacing: 14) {
            ForEach(Tab.allCases) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.label.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(tab == candidate ? OmniTheme.accent : OmniTheme.inkSoft)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(tab == candidate ? OmniTheme.accent : OmniTheme.hairline).frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 10)
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
        .task {
            if apiKeyIDInput.isEmpty, let remembered = appEnvironment.quotaAPIKeyID {
                apiKeyIDInput = remembered
                await load()
            }
            await loadRateLimitStatus()
        }
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
            // Only remembered on a confirmed-working load, never on a typo.
            appEnvironment.rememberQuotaAPIKeyID(apiKeyIDInput)
            await appEnvironment.refreshGlobalQuota()
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

// MARK: - Latency & success-rate analytics (undocumented exact field names)

private struct LatencyStatsSectionView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var stats: [AdminRawSnapshot] = []
    @State private var loadState: LoadState = .loading

    private enum LoadState: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                OmniTheme.label("Latence & succès par fournisseur/modèle", size: 9, color: OmniTheme.inkSoft)
                Text("GET /api/usage/model-latency-stats — moyenne/p50/p95/p99 et taux de succès, agrégés sur une fenêtre glissante. Champs exacts non documentés, affichés tels quels.")
                    .font(OmniTheme.serif(11).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            centeredMessage("Chargement…")
        case .failed(let message):
            centeredMessage(message)
        case .loaded:
            if stats.isEmpty {
                centeredMessage("Aucune donnée de latence pour l'instant.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(stats) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.id)
                                    .font(OmniTheme.mono(10, weight: .semibold))
                                    .foregroundStyle(OmniTheme.ink)
                                RawFieldRows(entries: entry.sortedEntries)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func load() async {
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            stats = try await client.listModelLatencyStats()
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
