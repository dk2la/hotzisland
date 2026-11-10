import Foundation

/// `LicenseAPI` backed by the Lemon Squeezy License API
/// (https://docs.lemonsqueezy.com/api/license-api). The endpoints are public:
/// the License key itself is the credential, so no API key ships in the app.
///
/// Deliberately conservative: only an explicit, decodable answer from the
/// store counts as "invalid". Timeouts, HTTP 429/5xx and unreadable bodies are
/// `.network`, because a wrong "invalid" locks a paying customer out.
struct LemonSqueezyLicenseAPI: LicenseAPI {
    /// One HTTP round trip. Injected so tests can answer with canned bodies.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let transport: Transport

    init(transport: @escaping Transport = LemonSqueezyLicenseAPI.urlSession) {
        self.transport = transport
    }

    /// Default transport: an ephemeral session, so nothing is cached on disk.
    static let urlSession: Transport = { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    // MARK: - LicenseAPI

    func activate(licenseKey: String, activationName: String) async throws -> LicenseActivation {
        let answer = try await post("activate", [("license_key", licenseKey), ("instance_name", activationName)])
        switch answer.activated {
        case true?:
            guard let activationID = answer.instance?.id, let productID = answer.meta?.productId else {
                throw LicenseAPIError.network
            }
            return LicenseActivation(activationID: activationID, productID: productID)
        case false?:
            throw answer.isActivationLimitReached
                ? LicenseAPIError.activationLimitReached
                : LicenseAPIError.invalidKey
        case nil:
            throw LicenseAPIError.network
        }
    }

    func validate(licenseKey: String, activationID: String) async throws -> LicenseValidity {
        let answer = try await post("validate", [("license_key", licenseKey), ("instance_id", activationID)])
        switch answer.valid {
        case true?: return .valid
        case false?: return .invalid
        case nil: throw LicenseAPIError.network
        }
    }

    func deactivate(licenseKey: String, activationID: String) async throws {
        let answer = try await post("deactivate", [("license_key", licenseKey), ("instance_id", activationID)])
        switch answer.deactivated {
        case true?: return
        case false?: throw LicenseAPIError.invalidKey
        case nil: throw LicenseAPIError.network
        }
    }

    // MARK: - Wire

    /// Sends one form-encoded POST and decodes the body. Throws `.network`
    /// for everything that is not a trustworthy answer from the store.
    private func post(_ action: String, _ fields: [(name: String, value: String)]) async throws -> LemonSqueezyAnswer {
        guard let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/" + action) else {
            throw LicenseAPIError.network
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncoded(fields).utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw LicenseAPIError.network
        }
        // Errors the store reports about a key are 4xx (400/404/422). A 429
        // or 5xx says nothing about the key, whatever its body claims.
        guard response.statusCode != 429, (200..<500).contains(response.statusCode) else {
            throw LicenseAPIError.network
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let answer = try? decoder.decode(LemonSqueezyAnswer.self, from: data) else {
            throw LicenseAPIError.network
        }
        return answer
    }

    /// `application/x-www-form-urlencoded` body. Everything outside the
    /// RFC 3986 unreserved set is escaped, so `+`, `&` and `=` survive.
    private static func formEncoded(_ fields: [(name: String, value: String)]) -> String {
        var unreserved = CharacterSet()
        unreserved.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return fields
            .map { field in
                let value = field.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
                return field.name + "=" + value
            }
            .joined(separator: "&")
    }
}

/// The parts of a License API response Pocket reads. Every field is
/// optional: which outcome flag is present depends on the endpoint, and
/// failures carry `null` objects. Decoded with `.convertFromSnakeCase`.
private struct LemonSqueezyAnswer: Decodable {
    var activated: Bool?
    var valid: Bool?
    var deactivated: Bool?
    var error: String?
    var licenseKey: Key?
    var instance: Instance?
    var meta: Meta?

    struct Key: Decodable {
        var status: String?
        /// `null` for a License with unlimited Activations.
        var activationLimit: Int?
        var activationUsage: Int?
    }

    struct Instance: Decodable {
        var id: String
    }

    struct Meta: Decodable {
        var productId: Int
    }

    /// Why a refused Activation was refused: the store's message says so
    /// ("This license key has reached the activation limit."), with the
    /// usage counters as a fallback should the wording change. A disabled
    /// or expired key is never a limit problem, however full it is.
    var isActivationLimitReached: Bool {
        if error?.localizedCaseInsensitiveContains("activation limit") == true {
            return true
        }
        guard let licenseKey, licenseKey.status != "disabled", licenseKey.status != "expired",
              let limit = licenseKey.activationLimit, let usage = licenseKey.activationUsage
        else { return false }
        return usage >= limit
    }
}
