import Foundation

/// Talks to the Trial server (`worker/`): `POST /trial` with the hashed
/// Mac ID answers with the Trial start date (created on first call) and the
/// server's current time.
struct TrialServerClient: TrialServer {
    enum Failure: Error {
        case notConfigured
        case badAnswer
    }

    private struct Answer: Decodable {
        let trialStartedAt: Double
        let serverTime: Double
    }

    let baseURL: URL?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    func trial(macID: String) async throws -> TrialStatus {
        guard let baseURL else { throw Failure.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("trial"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["macId": macID])
        let (data, response) = try await Self.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(Answer.self, from: data),
              answer.trialStartedAt > 0, answer.serverTime >= answer.trialStartedAt else { throw Failure.badAnswer }
        return TrialStatus(
            start: Date(timeIntervalSince1970: answer.trialStartedAt),
            serverNow: Date(timeIntervalSince1970: answer.serverTime)
        )
    }
}
