@testable import PalkieTalkie
import XCTest

final class FakeWeatherFetcher: WeatherHTTPFetcher, @unchecked Sendable {
    var responseData: Data
    var error: Error?

    init(responseData: Data, error: Error? = nil) {
        self.responseData = responseData
        self.error = error
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        if let error { throw error }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

final class WeatherContextTests: XCTestCase {
    func testParsesSampleOpenMeteoResponse() async {
        // Real Open-Meteo /v1/forecast response shape, trimmed to fields we read.
        let raw = """
        {
          "current": {
            "temperature_2m": 12.3,
            "weather_code": 3
          }
        }
        """
        let json = Data(raw.utf8)
        let fetcher = FakeWeatherFetcher(responseData: json)
        let weather = WeatherContext(fetcher: fetcher)

        let reading = await weather.current(lat: 35.68, lon: 139.76)
        XCTAssertEqual(reading?.temperatureC, 12.3)
        XCTAssertEqual(reading?.description, "overcast")
    }

    func testNetworkErrorReturnsNil() async {
        let fetcher = FakeWeatherFetcher(
            responseData: Data(),
            error: URLError(.notConnectedToInternet)
        )
        let weather = WeatherContext(fetcher: fetcher)
        let reading = await weather.current(lat: 0, lon: 0)
        XCTAssertNil(reading)
    }

    func testWeatherCodeDescriptions() {
        XCTAssertEqual(WeatherContext.weatherCodeDescription(0), "clear sky")
        XCTAssertEqual(WeatherContext.weatherCodeDescription(2), "mostly clear")
        XCTAssertEqual(WeatherContext.weatherCodeDescription(45), "foggy")
        XCTAssertEqual(WeatherContext.weatherCodeDescription(63), "rainy")
        XCTAssertEqual(WeatherContext.weatherCodeDescription(95), "thunderstorms")
        XCTAssertEqual(WeatherContext.weatherCodeDescription(999), "mixed weather")
    }
}
