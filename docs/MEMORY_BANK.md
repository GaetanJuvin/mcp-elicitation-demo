## Memory Bank: How This Project Works

### Core Idea
Minimal Model Context Protocol (MCP) demo showcasing client-side "elicitation" during a tool call. The server asks the client for missing inputs (e.g., a stock ticker) and the client prompts the user and replies.

### Components
- `mcp_client.rb`: JSON-RPC client that declares `elicitation` capability, lists tools, calls `get_stock_price`, and handles `elicitation/create`. Verbose mode prints colored I/O.
- `mcp_server.rb`: JSON-RPC server exposing `get_stock_price`. If ticker is missing, sends `elicitation/create` and waits for client response. Encapsulated in `Server#run!`.
- `price.rb`: Fetches and parses quotes from `stooq.com` via CSV. Provides `fetch_quote` and helpers in `StockPrice` module.
- `README.md`: How to run, example transcript, and link to spec.

### Protocol Flow (Happy Path)
1) Client → Server: `initialize` with `{ capabilities: { elicitation: {} } }`
2) Server → Client: `initialize` result with capabilities
3) Client → Server: `tools/list`
4) Server → Client: tool list including `get_stock_price`
5) Client → Server: `tools/call` for `get_stock_price` (maybe missing ticker)
6) Server → Client: `elicitation/create` requesting `{ ticker: string }`
7) Client: prompts user locally, builds result
8) Client → Server: result for `elicitation/create`
9) Server: fetches price, returns result in `tools/call` response

### Key Functions & Classes
- Client
  - `write_jsonrpc`, `read_jsonrpc`
  - `handle_elicitation`, `build_elicitation_response`
  - `TerminalColor` for colored logs
- Server
  - `JsonRpcTransport.write_message`, `.read_message`
  - `Server#run!` main loop
  - `Server#elicit_request` for elicitation
- Price
  - `StockPrice.build_quote_uri`
  - `StockPrice.fetch_raw_csv_rows`
  - `StockPrice.parse_rows_to_quote`
  - `fetch_quote` delegator

### Run Commands
```bash
ruby mcp_client.rb --server ./mcp_server.rb -v
ruby mcp_client.rb --server ./mcp_server.rb --ticker NVDA -v
```

### Troubleshooting
- No output: ensure paths are correct and Ruby version is 3.1+.
- HTTP error: network or `stooq.com` availability.
- CSV parse error: provider response format changed.

### Reference
- MCP Elicitation (Draft): https://modelcontextprotocol.io/specification/draft/client/elicitation


