# External agent harnesses: optional desktop/server adapters

Status: proposal, not implemented. Work package W20. No named adopter or external runtime has been selected.

The proposed user is a desktop or server application that needs to operate an existing coding-agent session while presenting its progress in the same conversation UI. Admission requires one named runtime/version, one concrete application, a runtime owner, and explicit rules for filesystem access, tool approvals, credentials and process lifetime.

## Boundary and interface

Expose an adapter for a remote or local agent session: create, observe, send input, approve a bound request, interrupt and close. Preserve runtime session IDs separately from conversation/message IDs. Map known events into conversation parts, retaining unknown events as opaque extensions. An interrupted process and a completed agent turn are distinct outcomes.

Do not put process launching into provider-neutral model interfaces. A local adapter may use `Process`; a hosted adapter uses the runtime's supported transport. Both must describe where code executes and who owns the environment. A Dart isolate or subprocess is not a security sandbox.

## Proof before support

- Use a pinned real runtime with deterministic workspaces and no production credentials.
- Verify startup failure, malformed events, cancellation during tool execution, process exit without a terminal event, and concurrent sessions.
- Verify approval requests cannot be replayed against modified commands or a different workspace.
- Confirm close terminates owned processes/subscriptions and leaves caller-owned services running.
- Test filesystem/network/resource isolation separately if the product claims a sandbox. Specify the actual enforcing mechanism and permitted operations.
- Compare adapter output against the runtime's own event log and preserve opaque fields required for resumption.

The benefit is reuse of established agent runtimes and familiar UI state. Costs include runtime installation, platform support, version coupling and an execution trust boundary. A mobile client should normally reach the harness through a trusted backend rather than launch it locally.

Reference: [Vercel HarnessAgent](https://ai-sdk.dev/docs/ai-sdk-harnesses/harness-agent).
