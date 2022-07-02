
import Foundation

struct Stock: Decodable {
    let symbol: String
    let trailingAnnualDividendYield: Double?
    let trailingPE: Double?
    let averageAnalystRating: String?
    let marketCap: Int?
    let epsTrailingTwelveMonths: Double?
}

struct QuoteResponse: Decodable {
    let result: [Stock]
}

struct StockResponse: Decodable {
    let quoteResponse: QuoteResponse
}

enum APIClientError: Error {
    case invalidRequest(Error)
    case decodingError(Error)
    case invalidResponse
    case dataLoadingError(statusCode: Int, data: Data)
    case generic
    case validError
}

class APIClient {
    private let session: URLSession = URLSession.shared

    func saveStocks(symbols: [String], apiKey: String, pathUrl: URL) async throws {
        let parameters = [
            "region": "US",
            "lang": "en",
            "symbols": symbols.joined(separator: ",")
        ]
        var components = URLComponents(string: "https://yfapi.net/v6/finance/quote")!
        components.queryItems = parameters.map({ (key, value) -> URLQueryItem in
            URLQueryItem(name: key, value: String(value))
        })
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIClientError.invalidResponse
        }

        let fileUrl = pathUrl.appendingPathComponent("stocks-\(symbols[0]).json")
        try data.write(to: fileUrl)
    }

    func stocks(symbols: [String], pathUrl: URL) async throws -> [Stock] {
        let fileUrl = pathUrl.appendingPathComponent("stocks-\(symbols[0]).json")
        do {
            let data = try Data(contentsOf: fileUrl)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(StockResponse.self, from: data)
            return decoded.quoteResponse.result
        } catch {
            return []
        }
    }
}
