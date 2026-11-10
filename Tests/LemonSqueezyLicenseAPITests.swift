import XCTest

/// Bodies are modelled on the examples in the Lemon Squeezy License API docs.
final class LemonSqueezyLicenseAPITests: XCTestCase {
    /// Records what the client sent; the transport is called off the test's
    /// own task, hence the actor.
    private actor Recorder {
        private(set) var requests: [URLRequest] = []

        func record(_ request: URLRequest) {
            requests.append(request)
        }
    }

    private func api(status: Int, body: String, recorder: Recorder? = nil) -> LemonSqueezyLicenseAPI {
        LemonSqueezyLicenseAPI { request in
            await recorder?.record(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { throw URLError(.badURL) }
            return (Data(body.utf8), response)
        }
    }

    private var offline: LemonSqueezyLicenseAPI {
        LemonSqueezyLicenseAPI { _ in throw URLError(.notConnectedToInternet) }
    }

    private func assertThrows<T: Sendable>(
        _ expected: LicenseAPIError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ call: () async throws -> T
    ) async {
        do {
            _ = try await call()
            XCTFail("expected \(expected), but the call returned", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LicenseAPIError, expected, file: file, line: line)
        }
    }

    private static let keyJSON = """
    {"id": 1, "status": "active", "key": "38b1460a-5104-4067-a91d-77b872934d51",
     "activation_limit": 3, "activation_usage": 1,
     "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null}
    """

    private static let metaJSON = """
    {"store_id": 1, "order_id": 2, "order_item_id": 3, "product_id": 4, "product_name": "Pocket",
     "variant_id": 5, "variant_name": "Default", "customer_id": 6, "customer_name": "John Doe",
     "customer_email": "johndoe@example.com"}
    """

    private static let instanceJSON = """
    {"id": "f90ec370-fd83-46a5-8bbd-44a241e78665", "name": "Test Mac", "created_at": "2021-01-24T14:15:07.000000Z"}
    """

    private static let notFoundJSON = """
    "error": "license_key not found.", "license_key": null, "instance": null, "meta": null}
    """

    // MARK: - Requests

    func testActivateSendsFormEncodedPost() async throws {
        let recorder = Recorder()
        let body = """
        {"activated": true, "error": null, "license_key": \(Self.keyJSON),
         "instance": \(Self.instanceJSON), "meta": \(Self.metaJSON)}
        """
        _ = try await api(status: 200, body: body, recorder: recorder)
            .activate(licenseKey: "AB+C&D=E/F", activationName: "Данила's Mac #1")

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.lemonsqueezy.com/v1/licenses/activate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(
            String(bytes: request.httpBody ?? Data(), encoding: .utf8),
            "license_key=AB%2BC%26D%3DE%2FF"
                + "&instance_name=%D0%94%D0%B0%D0%BD%D0%B8%D0%BB%D0%B0%27s%20Mac%20%231"
        )
    }

    func testValidateAndDeactivateSendKeyAndInstance() async throws {
        let recorder = Recorder()
        let validBody = """
        {"valid": true, "error": null, "license_key": \(Self.keyJSON),
         "instance": \(Self.instanceJSON), "meta": \(Self.metaJSON)}
        """
        _ = try await api(status: 200, body: validBody, recorder: recorder)
            .validate(licenseKey: "KEY-1", activationID: "inst-1")
        let deactivatedBody = """
        {"deactivated": true, "error": null, "license_key": \(Self.keyJSON), "meta": \(Self.metaJSON)}
        """
        try await api(status: 200, body: deactivatedBody, recorder: recorder)
            .deactivate(licenseKey: "KEY-1", activationID: "inst-1")

        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.url?.absoluteString), [
            "https://api.lemonsqueezy.com/v1/licenses/validate",
            "https://api.lemonsqueezy.com/v1/licenses/deactivate",
        ])
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(
            requests.map { String(bytes: $0.httpBody ?? Data(), encoding: .utf8) },
            ["license_key=KEY-1&instance_id=inst-1", "license_key=KEY-1&instance_id=inst-1"]
        )
    }

    // MARK: - Activate

    func testActivateReturnsInstanceAndProduct() async throws {
        let body = """
        {"activated": true, "error": null, "license_key": \(Self.keyJSON),
         "instance": \(Self.instanceJSON), "meta": \(Self.metaJSON)}
        """
        let activation = try await api(status: 200, body: body).activate(licenseKey: "KEY-1", activationName: "Test Mac")
        XCTAssertEqual(activation, LicenseActivation(activationID: "f90ec370-fd83-46a5-8bbd-44a241e78665", productID: 4))
    }

    func testActivateUnknownKeyIsInvalidKey() async {
        let api = api(status: 404, body: "{\"activated\": false, " + Self.notFoundJSON)
        await assertThrows(.invalidKey) { try await api.activate(licenseKey: "nope", activationName: "Test Mac") }
    }

    /// A disabled key is invalid even when all its Activations are used up.
    func testActivateDisabledKeyIsInvalidKey() async {
        let body = """
        {"activated": false, "error": "This license key has been disabled.",
         "license_key": {"id": 1, "status": "disabled", "key": "38b1460a-5104-4067-a91d-77b872934d51",
                         "activation_limit": 3, "activation_usage": 3,
                         "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
         "meta": \(Self.metaJSON)}
        """
        let api = api(status: 400, body: body)
        await assertThrows(.invalidKey) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
    }

    func testActivateExpiredKeyIsInvalidKey() async {
        let body = """
        {"activated": false, "error": "This license key has expired.",
         "license_key": {"id": 1, "status": "expired", "key": "38b1460a-5104-4067-a91d-77b872934d51",
                         "activation_limit": 3, "activation_usage": 1,
                         "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": "2022-01-24T14:15:07.000000Z"},
         "meta": \(Self.metaJSON)}
        """
        let api = api(status: 400, body: body)
        await assertThrows(.invalidKey) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
    }

    /// The documented error example, verbatim wording.
    func testActivateLimitReachedByMessage() async {
        let body = """
        {"activated": false, "error": "This license key has reached the activation limit.",
         "license_key": {"id": 1, "status": "active", "key": "38b1460a-5104-4067-a91d-77b872934d51",
                         "activation_limit": 5, "activation_usage": 5,
                         "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
         "meta": \(Self.metaJSON)}
        """
        let api = api(status: 400, body: body)
        await assertThrows(.activationLimitReached) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
    }

    /// Should the wording change, the usage counters still tell.
    func testActivateLimitReachedByCounters() async {
        let body = """
        {"activated": false, "error": "No more devices can be added.",
         "license_key": {"id": 1, "status": "active", "key": "38b1460a-5104-4067-a91d-77b872934d51",
                         "activation_limit": 3, "activation_usage": 3,
                         "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
         "meta": \(Self.metaJSON)}
        """
        let api = api(status: 400, body: body)
        await assertThrows(.activationLimitReached) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
    }

    func testActivateNetworkFailures() async {
        let offline = offline
        await assertThrows(.network) { try await offline.activate(licenseKey: "KEY-1", activationName: "Test Mac") }

        // A refusal behind a 429 or 5xx is not trusted, whatever the body says.
        let refusal = "{\"activated\": false, " + Self.notFoundJSON
        let unreadable: [(status: Int, body: String)] = [
            (429, refusal),
            (500, refusal),
            (503, "<html>Service Unavailable</html>"),
            (200, "not json"),
            (200, "{}"),
            (422, "{\"message\": \"The license key field is required.\", \"errors\": {\"license_key\": [\"required\"]}}"),
            // Claims success but lacks the instance: nothing to store.
            (200, "{\"activated\": true, \"error\": null, \"license_key\": \(Self.keyJSON), \"meta\": \(Self.metaJSON)}"),
        ]
        for answer in unreadable {
            let api = api(status: answer.status, body: answer.body)
            await assertThrows(.network) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
        }
    }

    // MARK: - Validate

    func testValidateValid() async throws {
        let body = """
        {"valid": true, "error": null, "license_key": \(Self.keyJSON),
         "instance": \(Self.instanceJSON), "meta": \(Self.metaJSON)}
        """
        let validity = try await api(status: 200, body: body).validate(licenseKey: "KEY-1", activationID: "inst-1")
        XCTAssertEqual(validity, .valid)
    }

    func testValidateExplicitInvalid() async throws {
        let body = """
        {"valid": false, "error": "This license key has been disabled.",
         "license_key": {"id": 1, "status": "disabled", "key": "38b1460a-5104-4067-a91d-77b872934d51",
                         "activation_limit": 3, "activation_usage": 1,
                         "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
         "instance": \(Self.instanceJSON), "meta": \(Self.metaJSON)}
        """
        let validity = try await api(status: 200, body: body).validate(licenseKey: "KEY-1", activationID: "inst-1")
        XCTAssertEqual(validity, .invalid)
    }

    func testValidateNotFoundWithJSONBodyIsInvalid() async throws {
        let validity = try await api(status: 404, body: "{\"valid\": false, " + Self.notFoundJSON)
            .validate(licenseKey: "KEY-1", activationID: "gone")
        XCTAssertEqual(validity, .invalid)
    }

    func testValidateNetworkFailures() async {
        let offline = offline
        await assertThrows(.network) { try await offline.validate(licenseKey: "KEY-1", activationID: "inst-1") }

        let refusal = "{\"valid\": false, " + Self.notFoundJSON
        let unreadable: [(status: Int, body: String)] = [
            (429, refusal),
            (500, refusal),
            (502, "Bad Gateway"),
            (404, "<html>Not Found</html>"),
            (200, ""),
            (200, "{\"error\": \"Something went wrong.\"}"),
            (200, "{\"valid\": \"false\"}"),
        ]
        for answer in unreadable {
            let api = api(status: answer.status, body: answer.body)
            await assertThrows(.network) { try await api.validate(licenseKey: "KEY-1", activationID: "inst-1") }
        }
    }

    // MARK: - Deactivate

    func testDeactivateSucceeds() async throws {
        let body = """
        {"deactivated": true, "error": null,
         "license_key": {"id": 1, "status": "inactive", "key": "38b1460a-5104-4067-a91d-77b872934d51",
                         "activation_limit": 5, "activation_usage": 0,
                         "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
         "meta": \(Self.metaJSON)}
        """
        try await api(status: 200, body: body).deactivate(licenseKey: "KEY-1", activationID: "inst-1")
    }

    func testDeactivateRefusedIsInvalidKey() async {
        let api = api(status: 404, body: "{\"deactivated\": false, " + Self.notFoundJSON)
        await assertThrows(.invalidKey) { try await api.deactivate(licenseKey: "KEY-1", activationID: "gone") }
    }

    func testDeactivateNetworkFailures() async {
        let offline = offline
        await assertThrows(.network) { try await offline.deactivate(licenseKey: "KEY-1", activationID: "inst-1") }

        let refusal = "{\"deactivated\": false, " + Self.notFoundJSON
        let unreadable: [(status: Int, body: String)] = [
            (429, refusal),
            (500, refusal),
            (200, "not json"),
            (200, "{}"),
        ]
        for answer in unreadable {
            let api = api(status: answer.status, body: answer.body)
            await assertThrows(.network) { try await api.deactivate(licenseKey: "KEY-1", activationID: "inst-1") }
        }
    }
}
