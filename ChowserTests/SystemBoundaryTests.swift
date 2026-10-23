import Foundation
import Network
import Testing
@testable import Chowser

@Suite(.serialized)
struct MetadataNetworkTests {
    @Test("Real loopback HTTP preview bounds the body, reports HTTP errors and rejects non-web URLs")
    func previewHTTPBoundary() async throws {
        let server = try MetadataHTTPFixture()
        let base = try await server.start()
        defer { server.stop() }
        let large = await LinkMetadataFetcher.fetch(base.appendingPathComponent("large"))
        guard case .metadata(let metadata) = large else { Issue.record("Expected metadata from local HTTP"); return }
        #expect(metadata.title == "Loopback lab")
        #expect(metadata.description == nil, "Metadata after the one-megabyte boundary must not be parsed")
        #expect(await LinkMetadataFetcher.fetch(base.appendingPathComponent("missing")) == .unavailable(503))
        #expect(await LinkMetadataFetcher.fetch(URL(fileURLWithPath: "/not-a-network-preview")) == .failed)
        #expect(await LinkMetadataFetcher.fetch(base.appendingPathComponent("disconnect")) == .failed)
    }
}

/// Binds only 127.0.0.1 on an ephemeral port and serves synthetic bytes.
private final class MetadataHTTPFixture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Chowser.MetadataHTTPFixture")
    private let listener: NWListener

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                if request.contains("/disconnect") { connection.cancel(); return }
                let missing = request.contains("/missing")
                let body = missing ? "unavailable" : "<title>Loopback lab</title>" + String(repeating: " ", count: 1_100_000)
                    + "<meta name=\"description\" content=\"outside the boundary\">"
                let header = "HTTP/1.1 \(missing ? "503 Service Unavailable" : "200 OK")\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data((header + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port else {
                        continuation.resume(throwing: URLError(.cannotConnectToHost)); return
                    }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)")!)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }
}

@MainActor
struct SystemBrowserBoundaryTests {
    @Test("Both real macOS launch paths report failure for a nonexistent app",
          arguments: [false, true])
    func missingBrowserReportsFailure(_ directOpen: Bool) async {
        let launcher = SystemBrowserLauncher()
        #expect(launcher.applicationURL(for: "invalid.chowser.lab.missing-browser") == nil)
        let plan = BrowserManager.BrowserLaunchPlan(
            mode: .directDownload, bundleId: "invalid.chowser.lab.missing-browser",
            appURL: URL(fileURLWithPath: "/private/tmp/chowser-nonexistent-\(UUID().uuidString).app"),
            documentURLs: [URL(string: "https://synthetic.invalid/")!], requestedApplicationArguments: [],
            deliveredApplicationArguments: directOpen ? ["--lab"] : [], argumentType: nil,
            applicationArgumentsSupported: true, createsNewApplicationInstance: false)
        let failure = await withCheckedContinuation { continuation in
            launcher.launch(plan) { continuation.resume(returning: $0) }
        }
        #expect(failure?.isEmpty == false)
    }
}
