import Foundation

/// Typed errors surfaced by ``APIClient``. The sync engine and UI branch on these
/// to decide whether to retry, queue, raise a conflict, or prompt re-authentication.
enum APIError: Error, Equatable {
    /// No network / server unreachable. Safe to keep the mutation queued and retry later.
    /// `reason` separates genuinely offline from the failures that look identical to the user but
    /// need a completely different fix — a self-signed certificate, a hostname that doesn't
    /// resolve, a server that never answers. Self-hosting makes those the common case, not the
    /// exotic one.
    case offline(reason: TransportFailure = .offline)
    /// 401 — token rejected. Session should be invalidated and the user re-prompted.
    case unauthorized
    /// 403 — authenticated but not permitted.
    case forbidden
    /// 404 — the record no longer exists on the server (drives delete-vs-edit conflicts).
    case notFound
    /// 409 or a detected concurrent modification.
    case conflict
    /// Any 5xx. Transient; retry with backoff.
    case server(status: Int)
    /// 4xx other than the above (validation errors etc.). Carries the server's message if any,
    /// plus the field names the server named (`fields`) — the keys of a DRF validation body. The
    /// keys alone are safe to report; the messages can quote what the user typed.
    case badRequest(status: Int, message: String?, fields: [String] = [])
    /// Response body could not be decoded into the expected type.
    case decoding(String)
    /// The configured server URL is invalid.
    case invalidURL

    /// Why a request never got an answer. Derived from `URLError.Code`.
    enum TransportFailure: String {
        /// No route at all — airplane mode, connection lost, cellular data off.
        case offline
        /// The address doesn't resolve.
        case dns
        /// Resolved, but nothing accepted the connection (wrong port, server down, not on the LAN).
        case cannotConnect
        /// TLS refused: self-signed or expired certificate, or ATS blocking a plain-http address.
        case tls
        /// Connected, then nothing came back in time.
        case timeout
        case other

        init(_ code: URLError.Code) {
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .internationalRoamingOff:
                self = .offline
            case .cannotFindHost, .dnsLookupFailed:
                self = .dns
            case .cannotConnectToHost:
                self = .cannotConnect
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                 .clientCertificateRejected, .clientCertificateRequired,
                 .appTransportSecurityRequiresSecureConnection:
                self = .tls
            case .timedOut:
                self = .timeout
            default:
                self = .other
            }
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .server: return true
        default: return false
        }
    }

    /// What a sync queue should do with a row whose delivery just failed. The single place both
    /// the mutation queue and the image-upload queue classify a failure, so the two can't drift
    /// into contradictory retry behavior.
    ///
    /// The distinction that matters is *transport vs. verdict*: if the request never got an
    /// answer, nothing has been learned about the payload and retrying is right. If the server
    /// answered and rejected it, re-sending the same bytes will be rejected the same way.
    enum QueueOutcome {
        /// 401 — the token is dead. Invalidate the session; the whole queue waits for a new one.
        case signOut
        /// Offline, DNS, TLS, timeout, or 5xx. Connectivity or configuration state, not a verdict
        /// on the payload — a self-signed certificate is fixed on the device, not in the record.
        /// Stop the queue and retry the whole thing later.
        case retryLater
        /// The server answered and this exact payload can't succeed: a validation rejection, a
        /// permission refusal, a missing target, or a body we can't parse. Park the row.
        case blocked
        /// Record the error but leave the row eligible. 409 keeps the established conflict
        /// semantics, and an invalid URL resolves when the server setting is corrected — neither
        /// is a property of the payload.
        case recordAndRetry
    }

    var queueOutcome: QueueOutcome {
        switch self {
        case .unauthorized: return .signOut
        case .offline, .server: return .retryLater
        // `notFound` here is only what escapes `deliver()`'s own 404 handling — an image upload
        // whose target is gone, or a create against an endpoint this server version lacks. The
        // update/delete conflict and satisfied-delete paths intercept 404 before this.
        case .forbidden, .notFound, .badRequest, .decoding: return .blocked
        case .conflict, .invalidURL: return .recordAndRetry
        }
    }

    /// A server-side 5xx specifically (excludes `offline`). Used to skip a single failing kind
    /// during a bulk pull without aborting the whole sync, while still treating a lost
    /// connection as a hard stop.
    var isServer: Bool {
        if case .server = self { return true }
        return false
    }

    var userMessage: String {
        switch self {
        case .offline(.dns): return "Couldn't find that server address."
        case .offline(.cannotConnect):
            return "Couldn't reach the server. Check the address, and that you're on the same network as it."
        case .offline(.tls):
            return "The server's security certificate wasn't accepted. A self-signed certificate has to be trusted on this device first."
        case .offline(.timeout): return "The server took too long to respond."
        case .offline: return "No connection to the Baby Buddy server."
        case .unauthorized: return "Your API token was rejected. Please sign in again."
        case .forbidden: return "You don't have permission to do that."
        case .notFound: return "That record no longer exists on the server."
        case .conflict: return "This record was changed on the server."
        case .server(let status): return "Server error (\(status)). Please try again later."
        case .badRequest(_, let message, _): return message ?? "The server rejected the request."
        case .decoding(let detail): return "Couldn't read the server response. \(detail)"
        case .invalidURL: return "The server address is not valid."
        }
    }
}
