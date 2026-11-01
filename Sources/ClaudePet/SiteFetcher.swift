import Foundation

/// El cargador real del recorrido del sitio. Educado: sesion efimera (sin cookies ni cache), pausa antes de cada peticion,
/// limite de tamano y un User-Agent que dice quien es.
enum SiteFetcher {
    static let pause: UInt64 = 120_000_000          // 120 ms
    static let maxBytes = 1_500_000

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = ["User-Agent": "claudwler/1.0 (ClaudePet; recorrido de sitio)", "Accept": "text/html,application/xhtml+xml,text/plain;q=0.8,*/*;q=0.5"]
        return URLSession(configuration: config)
    }()

    static func fetch(_ url: URL) async -> FetchedPage {
        try? await Task.sleep(nanoseconds: pause)
        let started = Date()
        func ms() -> Int { Int(Date().timeIntervalSince(started) * 1000) }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return FetchedPage(status: 0, millis: ms(), finalURL: url.absoluteString, error: "respuesta rara") }
            return FetchedPage(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "",
                               body: String(decoding: data.prefix(maxBytes), as: UTF8.self), millis: ms(), finalURL: http.url?.absoluteString ?? url.absoluteString)
        } catch let error as URLError {
            let why: String
            switch error.code {
            case .timedOut: why = "sin respuesta"
            case .cannotFindHost, .dnsLookupFailed: why = "dominio no existe"
            case .cannotConnectToHost: why = "no responde"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .secureConnectionFailed: why = "certificado inválido"
            default: why = "error de red"
            }
            return FetchedPage(status: 0, millis: ms(), finalURL: url.absoluteString, error: why)
        } catch {
            return FetchedPage(status: 0, millis: ms(), finalURL: url.absoluteString, error: "error")
        }
    }
}
