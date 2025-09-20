require "net/http"
require "uri"
require "csv"

module StockPrice
  module_function

  def build_quote_uri(ticker_symbol)
    normalized_symbol = ticker_symbol.to_s.strip
    normalized_symbol = "NVDA" if normalized_symbol.empty?
    lowercased_symbol = normalized_symbol.downcase
    formatted_symbol = lowercased_symbol.include?(".") ? lowercased_symbol : "#{lowercased_symbol}.us"
    URI("https://stooq.com/q/l/?s=#{URI.encode_www_form_component(formatted_symbol)}&f=sd2t2ohlcvn&e=csv")
  end

  def fetch_raw_csv_rows(request_uri)
    http = Net::HTTP.new(request_uri.host, request_uri.port)
    http.use_ssl = request_uri.scheme == "https"
    request = Net::HTTP::Get.new(request_uri)
    request["User-Agent"] = "mcp-stock-price/1.0"
    response = http.request(request)
    raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    CSV.parse(response.body)
  end

  def parse_rows_to_quote(rows)
    raise "No data" if rows.empty?
    if rows.length == 1 || (rows[0][0] != "Symbol")
      values = rows[0]
      symbol, date, time, open, high, low, close, volume, name = values
    else
      values = rows[1]
      header_index = rows[0].each_with_index.to_h
      symbol = values[header_index["Symbol"]]
      date = values[header_index["Date"]]
      time = values[header_index["Time"]]
      open = values[header_index["Open"]]
      high = values[header_index["High"]]
      low = values[header_index["Low"]]
      close = values[header_index["Close"]]
      volume = values[header_index["Volume"]]
      name = values[header_index["Name"]]
    end
    raise "No symbol" if symbol.to_s.strip.empty?
    raise "No price" if close.to_s == "N/D"
    price_value = Float(close) rescue nil
    raise "Bad price" unless price_value
    { symbol: symbol.upcase, price: price_value, date: date, time: time, name: (name unless name == "N/D") }
  end
end

def fetch_quote(ticker_symbol = "NVDA")
  request_uri = StockPrice.build_quote_uri(ticker_symbol)
  rows = StockPrice.fetch_raw_csv_rows(request_uri)
  StockPrice.parse_rows_to_quote(rows)
end


