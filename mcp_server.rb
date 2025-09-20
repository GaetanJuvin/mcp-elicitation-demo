#!/usr/bin/env ruby
require "json"
require_relative "price"

module JsonRpcTransport
  module_function

  def write_message(payload)
    json_body = JSON.dump(payload)
    header = "Content-Length: #{json_body.bytesize}\r\n\r\n"
    STDOUT.write(header)
    STDOUT.write(json_body)
    STDOUT.flush
  end

  def read_message
    headers = {}
    while (line = STDIN.gets)
      line = line.chomp
      break if line.empty?
      header_key, header_value = line.split(":", 2)
      headers[header_key] = header_value.strip if header_key && header_value
    end
    content_length = headers["Content-Length"].to_i
    return nil if content_length <= 0
    body = STDIN.read(content_length)
    JSON.parse(body)
  end
end

class Server
  def run!
    loop do
      incoming_message = JsonRpcTransport.read_message
      break unless incoming_message
      request_id = incoming_message["id"]
      method_name = incoming_message["method"]
      begin
        case method_name
        when "initialize"
          JsonRpcTransport.write_message({ jsonrpc: "2.0", id: request_id, result: { protocolVersion: "2024-11-05", serverInfo: SERVER_INFO, capabilities: { tools: {}, elicitation: {} } } })
        when "tools/list"
          JsonRpcTransport.write_message({ jsonrpc: "2.0", id: request_id, result: { tools: TOOLS } })
        when "tools/call"
          params = incoming_message["params"] || {}
          tool_name = params["name"]
          if tool_name != "get_stock_price"
            raise "Unknown tool: #{tool_name}"
          end
          arguments = params["arguments"] || {}
          ticker_symbol = arguments["ticker"].to_s.strip
          if ticker_symbol.empty?
            elicited_result = elicit_request(
              "Which stock ticker would you like to look up?",
              {
                type: "object",
                properties: {
                  ticker: { type: "string", minLength: 1, description: "Ticker symbol like NVDA, AAPL" }
                },
                required: ["ticker"],
                additionalProperties: false
              }
            )
            if elicited_result.is_a?(Hash) && elicited_result["ticker"].to_s.strip != ""
              ticker_symbol = elicited_result["ticker"].to_s.strip
            else
              ticker_symbol = "NVDA"
            end
          end
          latest_quote = fetch_quote(ticker_symbol)
          JsonRpcTransport.write_message({ jsonrpc: "2.0", id: request_id, result: { content: [ { type: "text", text: JSON.dump(latest_quote) } ] } })
        else
          JsonRpcTransport.write_message({ jsonrpc: "2.0", id: request_id, error: { code: -32601, message: "Method not found" } })
        end
      rescue => e
        JsonRpcTransport.write_message({ jsonrpc: "2.0", id: request_id, error: { code: -32000, message: e.message } })
      end
    end
  end

  private

  def elicit_request(prompt_text, json_schema)
    request_id = "elic-#{Time.now.to_f}"
    JsonRpcTransport.write_message({ jsonrpc: "2.0", id: request_id, method: "elicitation/create", params: { message: prompt_text, schema: json_schema } })
    loop do
      response_message = JsonRpcTransport.read_message
      next unless response_message
      if response_message["id"] == request_id && response_message.key?("result")
        return response_message["result"]
      elsif response_message["method"]
        unexpected_method_request_id = response_message["id"]
        JsonRpcTransport.write_message({ jsonrpc: "2.0", id: unexpected_method_request_id, error: { code: -32601, message: "Method not handled during elicitation" } }) if unexpected_method_request_id
      end
    end
  end
end

SERVER_INFO = { name: "stock-price", version: "1.0.0" }

TOOLS = [
  {
    name: "get_stock_price",
    description: "Get latest stock price for any ticker",
    inputSchema: {
      type: "object",
      properties: { ticker: { type: "string", description: "Ticker e.g. NVDA" } },
      additionalProperties: false
    }
  }
]

if __FILE__ == $0
  Server.new.run!
end


