# MCP Apps: optional Flutter host experiment

Status: proposal, not implemented. Work package W20. A tool resource URI or ordinary HTML widget does not constitute MCP Apps support.

The proposed user is a Flutter application that must host a named MCP server's interactive tool UI. Admission requires that server/resource, target platforms, a host maintainer, and an agreed execution boundary. No named adopter is established in this repository.

## Host responsibilities

Keep UI hosting outside the pure Dart MCP transport and core SDK. Select a platform webview/iframe mechanism only after verifying the target platforms. The host owns resource loading, bridge negotiation, origin identity, navigation policy, permissions, lifecycle and accessibility. Tools remain subject to application approval; embedded content cannot gain an unrestricted tool channel from possessing a resource URL.

Map host-visible tool state to stable conversation/call IDs. Persist state only through a versioned codec that excludes credentials. Unknown bridge messages must not be interpreted as tool instructions. Resource loading and host teardown must be cancellable, and closing a view must release its bridge and owned resources.

## Proof required

Use a pinned real MCP Apps reference application. Test bridge negotiation, tool-result updates, view reload, host cancellation and disposal. Verify navigation/origin restrictions, permission denials, untrusted content, oversized messages, malformed bridge payloads and concurrent views. Verify keyboard focus, screen-reader navigation, large text, reduced motion and background/resume on each claimed platform.

Document limitations separately for Flutter web, iOS, Android and desktop. A browser-only demonstration does not qualify native webview behavior. Before stabilizing, measure loading latency, memory after repeated open/close cycles and resource cleanup.

The benefit is interactive tool-specific UI. Costs include embedded-browser dependencies, platform differences and a new content execution boundary. Existing native Flutter tool/approval widgets remain the default until this experiment proves useful.

Source: [MCP Apps overview](https://modelcontextprotocol.io/extensions/apps/overview).
