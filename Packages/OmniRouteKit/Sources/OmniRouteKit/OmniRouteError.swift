import Foundation

public enum OmniRouteError: Error, Equatable {
    case authenticationFailed
    case rateLimited(retryAfterSeconds: Double?)
    case network(description: String)
    case invalidResponse(statusCode: Int)
    case streamInterrupted
    case unknown(description: String)
}

extension OmniRouteError {
    public static func from(httpStatusCode: Int, retryAfterHeader: String?) -> OmniRouteError {
        switch httpStatusCode {
        case 401, 403:
            return .authenticationFailed
        case 429:
            return .rateLimited(retryAfterSeconds: retryAfterHeader.flatMap(Double.init))
        default:
            return .invalidResponse(statusCode: httpStatusCode)
        }
    }

    public static func from(urlError: URLError) -> OmniRouteError {
        .network(description: urlError.localizedDescription)
    }
}
