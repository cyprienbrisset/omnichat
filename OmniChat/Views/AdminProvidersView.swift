import SwiftUI
import OmniRouteKit

/// The concepts a provider row is likely to carry, pulled out of the raw
/// snapshot under several candidate key names (including one real shape
/// confirmed live: an OAuth-connected account, e.g. `authType: "oauth"` +
/// `providerSpecificData: {plan, tier, subscriptionTier, ...}`) — anything
/// not recognized here stays in the raw, collapsible fallback rather than
/// being guessed at.
private struct ProviderDisplayFields {
    let name: String?
    let providerType: String?
    let authType: String?
    let isActive: Bool?
    let testStatus: String?
    let priority: Double?
    let rateLimitProtection: Bool?
    let backoffLevel: Double?
    let plan: String?
    let tier: String?
    let subscriptionTier: String?
    /// Real, if present, hint of credential health — the closest this
    /// server's shape comes to the mockup's masked "secret" column
    /// (`apiKeyHealth`, nested in `providerSpecificData`).
    let apiKeyHealth: String?
    let rateLimitedUntil: String?
    /// The nearer of `tokenExpiresAt`/`expiresAt`, relative to now — most
    /// relevant for an OAuth connection whose token needs periodic refresh.
    let expiryDescription: String?
    let remainingFields: [(key: String, value: String)]

    private static let knownKeys: Set<String> = [
        "name", "label", "provider", "type", "providerType", "status", "enabled",
        "rateLimitedUntil", "id", "providerId", "_id", "slug", "email",
        "authType", "isActive", "testStatus", "priority", "rateLimitProtection",
        "backoffLevel", "tokenExpiresAt", "expiresAt",
    ]

    init(_ snapshot: AdminRawSnapshot) {
        func firstString(_ keys: [String]) -> String? {
            for key in keys {
                if case .string(let value)? = snapshot.fields[key] { return value }
            }
            return nil
        }
        func bool(_ key: String) -> Bool? {
            if case .bool(let value)? = snapshot.fields[key] { return value }
            return nil
        }
        func number(_ key: String) -> Double? {
            if case .number(let value)? = snapshot.fields[key] { return value }
            return nil
        }
        func nestedString(_ topKey: String, _ nestedKey: String) -> String? {
            guard case .object(let nested)? = snapshot.fields[topKey] else { return nil }
            if case .string(let value)? = nested[nestedKey] { return value }
            return nil
        }

        name = firstString(["name", "label", "email"])
        providerType = firstString(["provider", "type", "providerType"])
        authType = firstString(["authType"])
        isActive = bool("isActive")
        testStatus = firstString(["testStatus"])
        priority = number("priority")
        rateLimitProtection = bool("rateLimitProtection")
        backoffLevel = number("backoffLevel")
        plan = nestedString("providerSpecificData", "plan")
        tier = nestedString("providerSpecificData", "tier")
        subscriptionTier = nestedString("providerSpecificData", "subscriptionTier")
        apiKeyHealth = nestedString("providerSpecificData", "apiKeyHealth")
        rateLimitedUntil = firstString(["rateLimitedUntil"])
        expiryDescription = firstString(["tokenExpiresAt", "expiresAt"]).flatMap(AdminDateFormatting.relativeDescription)
        remainingFields = snapshot.sortedEntries.filter { !Self.knownKeys.contains($0.key) }
    }
}

private enum AdminDateFormatting {
    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter
    }()

    /// "expire dans 8 h" / "a expiré il y a 2 j" — falls back to `nil`
    /// (never a fabricated date) if the raw string isn't real ISO 8601.
    static func relativeDescription(for isoString: String) -> String? {
        guard let date = iso.date(from: isoString) else { return nil }
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

/// Folds the fields a card already surfaced prominently out of the raw
/// dump — expandable on demand, same "Afficher tout" pattern used for long
/// tool results in the chat thread, rather than a permanent wall of text.
/// Laid out two-per-row once expanded so a couple dozen leftover fields
/// read as a compact table, not a single tall column.
private struct CollapsibleRawFields: View {
    let collapsedLabel: String
    let entries: [(key: String, value: String)]
    @State private var isExpanded = false

    private static let columns = [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button(isExpanded ? "Masquer les détails bruts" : collapsedLabel) {
                    isExpanded.toggle()
                }
                .buttonStyle(.omniLink)
                if isExpanded {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
                        ForEach(entries, id: \.key) { entry in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.key)
                                    .font(OmniTheme.mono(8, weight: .semibold))
                                    .foregroundStyle(OmniTheme.inkSoft)
                                Text(entry.value)
                                    .font(OmniTheme.mono(9))
                                    .foregroundStyle(OmniTheme.ink)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Fournisseurs & clés (mockup 4b) — a real filterable table: every filter
/// chip is built from authType/providerType values actually present in the
/// fetched data, never the mockup's fixed categories (this server may never
/// report "gratuit" or "local", and a server that does would use whatever
/// term it actually returns).
struct AdminProvidersView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var providers: [AdminRawSnapshot] = []
    @State private var loadState: LoadState = .loading
    @State private var showingAddForm = false
    @State private var pendingDeletion: AdminRawSnapshot?
    @State private var actionError: String?
    @State private var testResultsByID: [String: String] = [:]
    @State private var activeFilter: String?
    @State private var isTestingAll = false

    private enum LoadState: Equatable {
        case loading, loaded, failed(String)
    }

    /// One chip per distinct real authType/providerType value found, plus a
    /// synthetic "en panne" filter driven by real signals (inactive, auth
    /// failure, or an active rate-limit lockout) — never a fixed list.
    private var filterOptions: [String] {
        var values = Set<String>()
        for provider in providers {
            let display = ProviderDisplayFields(provider)
            if let authType = display.authType { values.insert(authType) }
            if let providerType = display.providerType { values.insert(providerType) }
        }
        var ordered = values.sorted()
        if providers.contains(where: isDown) {
            ordered.append("en panne")
        }
        return ordered
    }

    private func isDown(_ provider: AdminRawSnapshot) -> Bool {
        let display = ProviderDisplayFields(provider)
        return display.isActive == false
            || display.testStatus?.lowercased().contains("fail") == true
            || display.testStatus?.lowercased().contains("error") == true
            || display.rateLimitedUntil != nil
    }

    private var filteredProviders: [AdminRawSnapshot] {
        guard let activeFilter else { return providers }
        if activeFilter == "en panne" {
            return providers.filter(isDown)
        }
        return providers.filter {
            let display = ProviderDisplayFields($0)
            return display.authType == activeFilter || display.providerType == activeFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            if let actionError {
                Text(actionError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
                    Text("Fournisseurs & clés")
                        .font(OmniTheme.serif(24, weight: .semibold))
                        .foregroundStyle(OmniTheme.ink)
                }
                Spacer()
                Button("Tout tester") { Task { await testAll() } }
                    .buttonStyle(.omniLink)
                    .disabled(isTestingAll || providers.isEmpty)
                Button("+ Ajouter un fournisseur") { showingAddForm = true }
                    .buttonStyle(.omniLink)
            }
            if case .loaded = loadState {
                Text("\(providers.count) fournisseur(s) — la forme exacte de /api/providers n'est documentée qu'en prose ; les champs reconnus (statut, type/auth, plan, expiration) sont mis en avant, le reste reste consultable en détail.")
                    .font(OmniTheme.serif(11).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            if !filterOptions.isEmpty {
                filterBar
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterChip(label: "Toutes \(providers.count)", isSelected: activeFilter == nil) { activeFilter = nil }
            ForEach(filterOptions, id: \.self) { option in
                let count = option == "en panne" ? providers.filter(isDown).count : providers.filter {
                    let display = ProviderDisplayFields($0)
                    return display.authType == option || display.providerType == option
                }.count
                filterChip(label: "\(option) \(count)", isSelected: activeFilter == option, isWarning: option == "en panne") {
                    activeFilter = option
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, isWarning: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(isSelected ? OmniTheme.railText : (isWarning ? OmniTheme.danger : OmniTheme.inkSoft))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? OmniTheme.rail : (isWarning ? OmniTheme.danger.opacity(0.12) : OmniTheme.paperMuted))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
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
            } else if filteredProviders.isEmpty {
                centeredMessage("Aucun fournisseur ne correspond à ce filtre.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredProviders) { provider in
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
        let display = ProviderDisplayFields(provider)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let isActive = display.isActive {
                    Circle()
                        .fill(isActive ? OmniTheme.success : OmniTheme.inkSoft)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(display.name ?? provider.id)
                        .font(OmniTheme.serif(16, weight: .semibold))
                        .foregroundStyle(OmniTheme.ink)
                    Text(provider.id)
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                    if let apiKeyHealth = display.apiKeyHealth {
                        Text("secret : \(apiKeyHealth)")
                            .font(OmniTheme.mono(9))
                            .foregroundStyle(OmniTheme.inkSoft)
                    }
                    badgeRow(display)
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
        .padding(.vertical, 14)
    }

    /// Every badge here only appears when its underlying real field was
    /// present — an OAuth connection and a plain API-key provider surface
    /// entirely different subsets, and that's fine.
    @ViewBuilder
    private func badgeRow(_ display: ProviderDisplayFields) -> some View {
        let items = badgeItems(display)
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    AdminBadge(text: item.text, color: item.color)
                }
            }
        }
    }

    private func badgeItems(_ display: ProviderDisplayFields) -> [(text: String, color: Color)] {
        var items: [(text: String, color: Color)] = []
        if let providerType = display.providerType {
            items.append((providerType, OmniTheme.accent))
        }
        if let authType = display.authType {
            items.append((authType, OmniTheme.accent))
        }
        if let testStatus = display.testStatus {
            items.append((testStatus, statusColor(testStatus)))
        }
        if let plan = display.plan {
            items.append(("plan \(plan)", OmniTheme.ink))
        }
        if let tier = display.tier {
            items.append(("tier \(tier)", OmniTheme.ink))
        } else if let subscriptionTier = display.subscriptionTier {
            items.append((subscriptionTier, OmniTheme.ink))
        }
        if let priority = display.priority {
            items.append(("priorité \(Int(priority))", OmniTheme.inkSoft))
        }
        if display.rateLimitProtection == true || (display.backoffLevel ?? 0) > 0 {
            items.append(("rate-limit", OmniTheme.warning))
        }
        if let rateLimitedUntil = display.rateLimitedUntil {
            items.append(("limité jusqu'à \(rateLimitedUntil)", OmniTheme.danger))
        }
        if let expiryDescription = display.expiryDescription {
            items.append((expiryDescription, OmniTheme.inkSoft))
        }
        return items
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active", "true", "enabled", "ok", "healthy": return OmniTheme.success
        case "false", "disabled", "inactive": return OmniTheme.inkSoft
        default: return OmniTheme.warning
        }
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

    private func testAll() async {
        isTestingAll = true
        defer { isTestingAll = false }
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask { await test(provider) }
            }
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
