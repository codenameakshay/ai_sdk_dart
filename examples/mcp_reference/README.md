# Pinned MCP interoperability fixture

Run from the repository root with Node.js 18+ and the Dart/Flutter toolchain:

```sh
make test-mcp-reference
```

The target installs the exact lockfile with lifecycle scripts disabled, then starts the TypeScript SDK server as a local subprocess through Dart's real stdio transport. No provider keys, accounts, external services, or tool side effects are involved. Installation needs access to the npm registry; subsequent execution is local.

The fixture pins `@modelcontextprotocol/sdk` **1.30.0**. Its published supported-version list includes `2025-06-18`; its latest version constant is `2025-11-25`. This test qualifies the Dart **legacy** path for initialization, tool discovery, Unicode input/output, an explicit tool error, continued use after that error, and shutdown. It does not certify the separate modern `2026-07-28` strategy, all legacy features, OAuth, or full MCP conformance.

Ordinary Dart test runs skip this external reference case unless `AI_SDK_MCP_REFERENCE=1`; the existing mock/loopback suite remains available without Node installation. A release should run this explicit target as well as the full local matrix.

Reference source: <https://github.com/modelcontextprotocol/typescript-sdk>. The package lock records the registry integrity hashes for reproducibility.
