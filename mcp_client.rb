#!/usr/bin/env ruby
require "json"
require "open3"
require "optparse"

module TerminalColor
  RESET = "\e[0m"
  CYAN  = "\e[36m"
  YELLOW = "\e[33m"

  def self.cyan(text)
    "#{CYAN}#{text}#{RESET}"
  end

  def self.yellow(text)
    "#{YELLOW}#{text}#{RESET}"
  end
end

class MCPClient
  def initialize(server_path:, ticker: nil, verbose: false)
    @server_path = server_path
    @ticker = ticker
    @verbose = verbose
  end

  def run
    Open3.popen3(@server_path) do |server_stdin, server_stdout, _server_stderr, server_wait_thread|
      begin
        initialize_request_id = new_id("init")
        write_jsonrpc(server_stdin, { jsonrpc: "2.0", id: initialize_request_id, method: "initialize", params: { clientInfo: { name: "mcp-client-ruby", version: "1.0.0" }, capabilities: { elicitation: {} } } })
        loop do
          response_message = read_jsonrpc(server_stdout)
          raise "Server exited" if response_message.nil?
          break if response_message["id"] == initialize_request_id
        end

        list_request_id = new_id("list")
        write_jsonrpc(server_stdin, { jsonrpc: "2.0", id: list_request_id, method: "tools/list" })
        available_tool_names = nil
        loop do
          response_message = read_jsonrpc(server_stdout)
          raise "Server exited" if response_message.nil?
          if response_message["id"] == list_request_id
            available_tool_names = (response_message.dig("result", "tools") || []).map { |tool| tool["name"] }
            break
          end
        end
        unless available_tool_names&.include?("get_stock_price")
          warn "Server does not expose expected tool. Available: #{available_tool_names.inspect}"
          return 2
        end

        call_request_id = new_id("call")
        tool_arguments = @ticker ? { ticker: @ticker } : {}
        write_jsonrpc(server_stdin, { jsonrpc: "2.0", id: call_request_id, method: "tools/call", params: { name: "get_stock_price", arguments: tool_arguments } })

        loop do
          response_message = read_jsonrpc(server_stdout)
          raise "Server exited" if response_message.nil?
          if response_message["method"] == "elicitation/create"
            handle_elicitation(server_stdin, response_message)
            next
          end
          if response_message["id"] == call_request_id
            render_result(response_message)
            break
          end
        end
        0
      ensure
        safe_close(server_stdin)
        safe_close(server_stdout)
        terminate(server_wait_thread)
      end
    end
  end

  private

  def write_jsonrpc(target_io, payload)
    json_payload = JSON.dump(payload)
    target_io.write("Content-Length: #{json_payload.bytesize}\r\n\r\n")
    target_io.write(json_payload)
    target_io.flush
    puts TerminalColor.cyan("→ #{json_payload}") if @verbose
  end

  def read_jsonrpc(source_io)
    headers = {}
    while (line = source_io.gets)
      line = line.chomp
      break if line.empty?
      header_key, header_value = line.split(":", 2)
      headers[header_key] = header_value.strip if header_key && header_value
    end
    body_length = headers["Content-Length"].to_i
    return nil if body_length <= 0
    body = source_io.read(body_length)
    puts TerminalColor.yellow("← #{body}") if @verbose
    JSON.parse(body)
  end

  def handle_elicitation(server_stdin, message)
    request_id = message["id"]
    params = message["params"] || {}
    prompt_message = params["message"] || "Input required"
    json_schema = params["schema"] || {}
    response_payload = build_elicitation_response(prompt_message, json_schema)
    write_jsonrpc(server_stdin, { jsonrpc: "2.0", id: request_id, result: response_payload })
  end

  def build_elicitation_response(prompt_message, json_schema)
    if json_schema.is_a?(Hash) && json_schema["properties"].is_a?(Hash) && json_schema["properties"].key?("ticker")
      ticker_value = if @ticker && !@ticker.to_s.strip.empty?
        @ticker.to_s.strip
      else
        prompt("#{prompt_message} ") { |input| input.empty? ? "NVDA" : input }
      end
      { "ticker" => ticker_value }
    else
      { "value" => prompt("#{prompt_message}: ") }
    end
  end

  def render_result(message)
    return warn("Error #{message.dig("error", "code")}: #{message.dig("error", "message")}") if message.key?("error")
    text_item = (message.dig("result", "content") || []).find { |content| content.is_a?(Hash) && content["type"] == "text" }&.fetch("text", nil)
    return puts(JSON.dump(message["result"])) unless text_item
    parsed_text = (JSON.parse(text_item) rescue nil)
    if parsed_text.is_a?(Hash) && parsed_text["symbol"] && parsed_text["price"]
      puts "#{parsed_text["symbol"]} #{parsed_text["price"]}"
    else
      puts text_item
    end
  end

  def new_id(prefix)
    "#{prefix}-#{(Time.now.to_f * 1000).to_i}-#{rand(1_000_000)}"
  end

  def safe_close(io)
    io.close unless io.closed?
  rescue
  end

  def terminate(server_wait_thread)
    Process.kill("TERM", server_wait_thread.pid) rescue nil
    Process.wait(server_wait_thread.pid) rescue nil
  end

  def prompt(text)
    puts text
    input_value = $stdin.gets&.chomp.to_s
    block_given? ? yield(input_value.strip) : input_value
  end
end

Options = Struct.new(:server_path, :ticker, :verbose)

def parse_options
  opts = Options.new(File.expand_path("./mcp_server.rb", __dir__), nil, false)
  OptionParser.new do |o|
    o.banner = "Usage: mcp_client.rb [options]"
    o.on("--server PATH", "Path to server executable (default: ./server.rb)") { |v| opts.server_path = v }
    o.on("--ticker TICKER", "Ticker symbol to use; if omitted, elicitation will prompt") { |v| opts.ticker = v }
    o.on("-v", "--verbose", "Verbose logging") { opts.verbose = true }
    o.on("-h", "--help", "Show help") { puts o; exit 0 }
  end.parse!
  opts
end

if __FILE__ == $0
  opts = parse_options
  unless File.exist?(opts.server_path)
    warn "Server not found: #{opts.server_path}"; exit 1
  end
  mcp_client = MCPClient.new server_path: opts.server_path, ticker: opts.ticker, verbose: opts.verbose

  puts "Running MCP client with server: #{opts.server_path} and ticker: #{opts.ticker}" if opts.verbose
  mcp_client.run
end


