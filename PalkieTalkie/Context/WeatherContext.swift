import Foundation

struct WeatherReading: Equatable {
    let description: String
    let temperatureC: Double
}

/// Networking seam for tests. Real impl is `URLSession.shared.data(from:)`, fake impl returns canned bytes / errors.
protocol WeatherHTTPFetcher: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: WeatherHTTPFetcher {}

/// Open-Meteo client. Free, no API key. Single endpoint, current conditions only.
actor WeatherContext {
    private let fetcher: WeatherHTTPFetcher

    init(fetcher: WeatherHTTPFetcher = URLSession.shared) {
        self.fetcher = fetcher
    }

    /// Returns nil on any error — context gathering is best-effort and must not throw out of the 1.5s start budget.
    func current(lat: Double, lon: Double) async -> WeatherReading? {
        let endpoint = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code"
        guard let url = URL(string: endpoint) else { return nil }
        do {
            let (data, _) = try await fetcher.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return WeatherReading(
                description: Self.weatherCodeDescription(decoded.current.weatherCode),
                temperatureC: decoded.current.temperature2m,
            )
        } catch {
            return nil
        }
    }

    /// WMO weather interpretation codes, condensed to natural English the persona can speak.
    static func weatherCodeDescription(_ code: Int) -> String {
        switch code {
        case 0: "clear sky"
        case 1, 2: "mostly clear"
        case 3: "overcast"
        case 45, 48: "foggy"
        case 51, 53, 55, 56, 57: "drizzle"
        case 61, 63, 65, 66, 67: "rainy"
        case 71, 73, 75, 77: "snowing"
        case 80, 81, 82: "rain showers"
        case 95, 96, 99: "thunderstorms"
        default: "mixed weather"
        }
    }
}

struct OpenMeteoCurrent: Decodable {
    let temperature2m: Double
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case weatherCode = "weather_code"
    }
}

struct OpenMeteoResponse: Decodable {
    let current: OpenMeteoCurrent
}
