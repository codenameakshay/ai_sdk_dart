# Admission of additional providers

Status: demand-gated W19 review. Existing adapters remain the v3 qualification target. No new provider is claimed as supported by this document.

The approved plan requires demand and ownership before enterprise/provider expansion. The repository and current task do not establish a named adopter, maintainer or live-test credentials for the candidates below. Adding renamed Chat Completions wrappers would not satisfy their native protocol requirements.

| Candidate | Concrete admission evidence needed | Adapter work to qualify |
| --- | --- | --- |
| OpenRouter | Application requiring its routing/account features and an owner | Routing and fallback metadata, billing/usage attribution, compatible endpoint differences, typed errors and cancellation |
| DeepSeek | Named model/workload and maintained API target | Reasoning continuation and tool/output semantics, native options, current request/stream fixtures |
| xAI | Named Responses workload and maintainer | Responses-native events and hosted tools; Chat-only support must be labeled as such |
| Vertex AI | Project/region and workload identity requirement | Token refresh, project/location routing, auth expiry, regional endpoints and provider-specific request semantics |
| AWS Bedrock | Region/model/inference profile and IAM owner | SigV4/session credentials, refresh, Converse/event-stream parsing, throttling and region routing |
| Firebase AI Logic | Flutter client application and supported platforms | Firebase initialization, app identity/App Check where configured, managed client SDK semantics and device lifecycle |

## Admission checklist

For a selected provider, record a named owner, user workload, official model/API source, auth flow, supported platform matrix and maintenance policy. Start with one useful end-to-end path. Preserve arbitrary model/deployment IDs; the catalog advises rather than rejects unknown IDs.

Qualification must include malformed and non-2xx responses, source errors after partial output, cancellation before and after request dispatch, actual socket closure, rate-limit handling and current protocol continuation. Verify provider token/image/file constraints independently from input-count limits. Test custom endpoints and headers only where that provider supports them.

A dated authenticated smoke test is required before describing support as live verified. Fixtures remain useful evidence but do not establish model availability, account access or regional rollout. Record the exact model, endpoint/API version, date and features exercised without storing credentials or private prompt content.

## Compatibility endpoint path

Applications may already use the OpenAI-compatible seam with their own base URL, headers and model ID. That is a protocol-level capability, not certification of every service behind a compatible endpoint. Its documentation must distinguish verified common behavior from provider-native features such as reasoning signatures, hosted tools, cache accounting and Responses events.

The expected benefit of admission is a maintained native integration for a demonstrated workload. Costs include provider release tracking, auth dependencies, extra tests and platform-specific behavior. No additional mandatory cloud SDK belongs in the core package solely to increase the provider count.

This gate does not reduce the existing v3 plan: it records the prerequisites that W19 explicitly requires. Once a candidate meets them, implement and qualify its adapter as a separate owned work package.
