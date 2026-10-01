# W17 implementation contract and primary evidence

Checked 2026-09-23 using the official OpenAI Docs retrieval and OpenAPI tools. This is a contract for the pending implementation, not a support claim.

Sources:

- [Files reference](https://developers.openai.com/api/reference/resources/files), OpenAPI endpoint `https://api.openai.com/v1/files`, API spec version 2.3.0.
- [Batch guide](https://developers.openai.com/api/docs/guides/batch).

## File lifecycle

The Files endpoint accepts multipart upload with `file` and `purpose`. The current reference also shows optional `expires_after[anchor]=created_at` and `expires_after[seconds]`. File metadata includes ID, byte count, creation/expiry times, filename and purpose. File IDs are opaque provider references, not URLs.

The initial adapter must expose upload, retrieve metadata, download content and explicit delete. Reuse the configured OpenAI client/base URL/auth provider; do not create hidden clients. Preserve caller ownership of injected clients. Upload input must work in pure Dart and Flutter web without requiring `dart:io.File`; bytes and a length-known byte stream are sufficient. MIME type and filename belong to the upload request, not a guessed file-ID extension.

Return a namespaced provider reference that Responses can serialize as `file_id`. A reference from another provider must fail explicitly rather than being sent as an arbitrary URL or silently omitted. Decode and persistence must not download references. Existing bytes/base64/URL input constructors remain usable.

Cancellation/deadlines cover auth acquisition, upload, waiting headers and download consumption. Local socket tests must observe peer closure; a failed Future alone does not prove transport cancellation. A cancelled upload with no returned ID may have an ambiguous remote outcome, so no automatic replay or invented deletion is allowed. Deleting a returned file is an explicit caller action; normal generation must not delete caller-owned input files.

## Experimental batch lifecycle

The current guide accepts a JSONL input file uploaded with purpose `batch`, then `POST /v1/batches` with `input_file_id`, `endpoint`, `completion_window: "24h"` and optional metadata. Every input row has a unique `custom_id`, method, URL and body. A file uses one model. The initial Dart adapter should qualify `/v1/responses` rather than promise every endpoint merely because the guide lists it.

Typed job states must preserve the server's distinctions: `validating`, `failed`, `in_progress`, `finalizing`, `completed`, `expired`, `cancelling`, `cancelled`. Preserve an unknown future status explicitly; never map it to success. Metadata exposes separate output and error file IDs and total/completed/failed request counts.

Result files are JSONL. Output order may differ from request order: associate results by `custom_id`, and retain each item’s HTTP status, request ID, response body or error. Reject duplicate result IDs or provide a documented explicit duplicate policy; never silently replace one result in a map. Partial results from expired/cancelled jobs remain available and must not be misreported as all-request success.

Expose create/get/list/cancel and an incremental result decoder. Server cancellation is an explicit operation: status may remain `cancelling` for up to ten minutes. Cancelling a local polling/download request does not cancel the server job. No implicit poll loop, resubmission or file cleanup should hide those separate lifetimes.

The guide states 50,000 requests and 200 MB per batch input file, plus a 50,000 total-input limit for embedding batches. Model availability and account limits remain service-dependent. These values are dated documentation, not proof that arbitrary future models support batching.

## Qualification

Use a loopback HTTP fixture that validates actual multipart upload and request paths/bodies, returns file metadata, accepts the resulting file reference in Responses, and implements batch status transitions. Include malformed metadata, auth failure, cancellation, delete acknowledgement mismatch, mixed per-item success/error, reversed output ordering, duplicate IDs, split UTF-8/JSONL boundaries and truncated final lines. Keep terminal errors typed and avoid retaining response bodies by default.

Provide a compiling upload/reference/delete example and a compiling experimental batch example with explicit ownership and cleanup. Live verification remains a distinct credentialed release gate; fixtures do not establish account/model availability or billed-job completion.
