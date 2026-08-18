import Foundation

extension OmniRouteClient {
    /// Whether the currently configured API key also carries management
    /// scope — checked by actually calling a real management-gated
    /// endpoint, never assumed from the key's shape or a setting. `/api/memory`
    /// is a lightweight, read-only list call that the API reference marks as
    /// requiring `requireManagementAuth`: a 2xx response means this key has
    /// management rights, 401/403 means it doesn't, and any other failure
    /// (network, unexpected status) is treated as "no" — this is a
    /// capability probe, not something to surface as a user-facing error.
    public func hasManagementAccess() async -> Bool {
        guard let request = try? authorizedManagementRequest(path: "api/memory") else { return false }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    /// The management API (`/api/*`) is a sibling of the OpenAI-compatible
    /// chat surface (`/v1/*`), not nested under it — so this derives the
    /// server root by stripping a trailing `/v1` from the configured base
    /// URL, rather than reusing `authorizedRequest`'s `/v1`-relative path.
    /// Same bearer key as every other call: this is capability, not identity.
    nonisolated func authorizedManagementRequest(path: String) throws -> URLRequest {
        var request = URLRequest(url: managementBaseURL.appendingPathComponent(path))
        if let apiKey = try credentialStore.apiKey(for: profile.id) {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    nonisolated var managementBaseURL: URL {
        if profile.baseURL.lastPathComponent.lowercased() == "v1" {
            return profile.baseURL.deletingLastPathComponent()
        }
        return profile.baseURL
    }
}
