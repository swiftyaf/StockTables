
import Algorithms
import TabularData
import Foundation
import ArgumentParser

@main
struct StockTables: AsyncParsableCommand {
    @Option(name: .long, help: "The input filename with full path")
    private var inputFile: String
    @Option(name: .long, help: "Whether to save data locally or use it to do analysis. Use 'save' or 'parse' or leave out to parse")
    private var mode: String?
    @Option(name: .long, help: "You API key for yahoofinanceapi.com")
    private var apiKey: String?

    func run() async throws {
        let fileUrl = URL(fileURLWithPath: inputFile)
        let pathUrl = fileUrl.deletingLastPathComponent()
        let shouldSave: Bool = (mode == "save")
        let options = CSVReadingOptions(hasHeaderRow: true, delimiter: ",")
        let fullDataFrame = try! DataFrame(contentsOfCSVFile: fileUrl,
                                           columns: ["Symbol", "Title", "Currency", "ISA_eligible", "PLUS_only"],
                                           types: ["Symbol": .string,
                                                   "Title": .string,
                                                   "ISA_eligible": .boolean,
                                                   "Currency": .string,
                                                   "PLUS_only": .boolean],
                                           options: options)
        let dataFrame = fullDataFrame
            .filter(on: "Currency", String.self, { $0 == "usd" })
            .filter(on: "ISA_eligible", Bool.self, { $0! })
            .filter(on: "PLUS_only", Bool.self, { $0! })
            .selecting(columnNames: "Symbol", "Title")

        print(dataFrame)
        let tickerData = dataFrame.selecting(columnNames: "Symbol")
        let symbolGroups = tickerData.rows.compactMap { row in
            (row["Symbol"] as! String)
        }.chunks(ofCount: 10)
        let rowCount = tickerData.rows.count

        if shouldSave {
            let apiClient = APIClient()
            guard let apiKey = apiKey else {
                print("Please provide an API key if you want to save stock data.")
                return
            }
            for symbolGroup in symbolGroups {
                try await apiClient.saveStocks(symbols: Array(symbolGroup), apiKey: apiKey, pathUrl: pathUrl)
            }
            print("Stock data saved!")
        } else {
            var symbolCol = Column<String>(name: "symbol", capacity: rowCount)
            var marketCapCol = Column<Int>(name: "marketCap", capacity: rowCount)
            var divCol = Column<Double>(name: "trailingAnnualDividendYield", capacity: rowCount)
            var peCol = Column<Double>(name: "trailingPE", capacity: rowCount)
            var ratingCol = Column<String>(name: "averageAnalystRating", capacity: rowCount)
            var epsCol = Column<Double>(name: "epsTrailingTwelveMonths", capacity: rowCount)
            var stocksDataFrame = DataFrame()

            let apiClient = APIClient()
            for symbolGroup in symbolGroups {
                let stocks = try await apiClient.stocks(symbols: Array(symbolGroup), pathUrl: pathUrl)
                for stock in stocks {
                    symbolCol.append(stock.symbol)
                    marketCapCol.append(stock.marketCap)
                    divCol.append(stock.trailingAnnualDividendYield)
                    peCol.append(stock.trailingPE)
                    ratingCol.append(stock.averageAnalystRating)
                    epsCol.append(stock.epsTrailingTwelveMonths)
                }
            }

            stocksDataFrame.append(column: symbolCol)
            stocksDataFrame.append(column: marketCapCol)
            stocksDataFrame.append(column: divCol)
            stocksDataFrame.append(column: peCol)
            stocksDataFrame.append(column: ratingCol)
            stocksDataFrame.append(column: epsCol)

            print(stocksDataFrame)

            let oneData = dataFrame.joined(stocksDataFrame, on: (left: "Symbol", right: "symbol"), kind: .left)
                .filter(on: "marketCap", Int.self, { $0 ?? 0 > 1000000000 })
                .filter(on: "epsTrailingTwelveMonths", Double.self, { $0 ?? 0 > 0 })
                .filter(on: "trailingAnnualDividendYield", Double.self, { $0 ?? 0 > 0.01 })
                .filter(on: "right.averageAnalystRating", String.self, { $0 ?? "2" <= "1.5" })
                .selecting(columnNames: "Symbol", "left.Title", "right.marketCap", "right.trailingAnnualDividendYield", "right.averageAnalystRating")

            print(oneData)

            let formatter = NumberFormatter()
            formatter.numberStyle = .percent
            formatter.maximumFractionDigits = 2

            var prettyData = DataFrame(oneData)
            prettyData.transformColumn("right.trailingAnnualDividendYield") { (val: Double) -> String in
                let number = NSNumber(value: val)
                let formattedValue = formatter.string(from: number)!
                return "\(formattedValue)"
            }
            prettyData.renameColumn("left.Title", to: "Company")
            prettyData.renameColumn("right.marketCap", to: "Market Cap")
            prettyData.renameColumn("right.trailingAnnualDividendYield", to: "Dividend Yield")
            prettyData.renameColumn("right.averageAnalystRating", to: "Average Analyst Rating")

            print(prettyData)
        }
    }
}
