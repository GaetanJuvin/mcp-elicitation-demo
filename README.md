## Stock Price MCP Server (Elicitation Demo)

This project is a minimal implementation of the Model Context Protocol (MCP) with client-side elicitation. It demonstrates how a server can request additional user input (like a stock ticker) via the client during a tool call, and how the client declares and handles the elicitation capability.

Reference: [MCP Elicitation (Draft)](https://modelcontextprotocol.io/specification/draft/client/elicitation)

### How it works

- **Client** (`mcp_client.rb`):
  - Declares the `elicitation` capability during `initialize`.
  - Sends `tools/list` and then `tools/call` for `get_stock_price`.
  - When the server asks for input (`elicitation/create`), it prompts locally and replies with the structured response.
  - Verbose mode prints colored I/O: **→** (cyan) for sent JSON, **←** (yellow) for received JSON.

- **Server** (`mcp_server.rb`):
  - Advertises the `get_stock_price` tool.
  - If the ticker argument is missing, sends an `elicitation/create` request to the client and waits for the client's response.
  - Returns the fetched quote as a JSON-encoded text content item.

- **Price fetch** (`price.rb`):
  - Fetches quotes from `stooq.com` and parses CSV to return `{ symbol, price, date, time, name }`.

### Run locally

Requirements: Ruby 3.1+

Optional (if you use Bundler):
```bash
bundle install
```

Run the client (it will spawn the server):
```bash
ruby mcp_client.rb --server ./mcp_server.rb -v
```

Provide a ticker upfront (skips elicitation):
```bash
ruby mcp_client.rb --server ./mcp_server.rb --ticker NVDA -v
```

### Example verbose session

Colors: **→** is sent (cyan), **←** is received (yellow). Output below is representative.

```text
→ {"jsonrpc":"2.0","id":"init-...","method":"initialize","params":{"clientInfo":{"name":"mcp-client-ruby","version":"1.0.0"},"capabilities":{"elicitation":{}}}}
← {"jsonrpc":"2.0","id":"init-...","result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"stock-price","version":"1.0.0"},"capabilities":{"tools":{},"elicitation":{}}}}

→ {"jsonrpc":"2.0","id":"list-...","method":"tools/list"}
← {"jsonrpc":"2.0","id":"list-...","result":{"tools":[{"name":"get_stock_price","description":"Get latest stock price for any ticker","inputSchema":{...}}]}}

→ {"jsonrpc":"2.0","id":"call-...","method":"tools/call","params":{"name":"get_stock_price","arguments":{}}}
← {"jsonrpc":"2.0","id":"elic-...","method":"elicitation/create","params":{"message":"Which stock ticker would you like to look up?","schema":{"type":"object","properties":{"ticker":{"type":"string","minLength":1,"description":"Ticker symbol like NVDA, AAPL"}},"required":["ticker"],"additionalProperties":false}}}

(prompt) Which stock ticker would you like to look up?
→ {"jsonrpc":"2.0","id":"elic-...","result":{"ticker":"NVDA"}}

← {"jsonrpc":"2.0","id":"call-...","result":{"content":[{"type":"text","text":"{\"symbol\":\"NVDA\",\"price\":123.45,\"date\":\"2025-09-20\",\"time\":\"15:59:00\"}"}]}}
NVDA 123.45
```

### Relevant code locations

- Client declares `elicitation` capability and handles `elicitation/create`:
```30:36:mcp_client.rb
initialize_request_id = new_id("init")
write_jsonrpc(server_stdin, { jsonrpc: "2.0", id: initialize_request_id, method: "initialize", params: { clientInfo: { name: "mcp-client-ruby", version: "1.0.0" }, capabilities: { elicitation: {} } } })
```

- Server sends `elicitation/create` when ticker is missing:
```78:91:mcp_server.rb
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
```

### Notes

- This example follows the MCP elicitation flow described in the spec and uses a simple prompt/response interaction. See the draft spec for details: [MCP Elicitation](https://modelcontextprotocol.io/specification/draft/client/elicitation).
- The client prints colored JSON-RPC traffic in verbose mode to make the flow easy to inspect.

### Further Reading

- Memory Bank (architecture, flow, components): `docs/MEMORY_BANK.md`
