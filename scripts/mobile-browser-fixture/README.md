# Mobile browser acceptance fixture

This disposable website supplies a real browser task and a separate record of its
server-side changes for [Browser #209](https://github.com/advatar/Browser/issues/209).
It is qualification infrastructure for the existing Swift/WebKit driver. Passing
these Node tests does not establish that an agent task has run on an iPhone.

The task is to read two synthetic sources, compose a short workshop brief and
submit it. **Typing saves changes before submission.** This deliberately exercises
a browser effect that cannot be governed solely at the final Submit button.

## Run

Use Node 24. No dependency installation or build step is required for this
directory.

```sh
npm run check:mobile-browser-fixture
npm run test:mobile-browser-fixture
npm run dev:mobile-browser-fixture
```

Open the printed fixture URL, normally `http://127.0.0.1:4877`. The CLI prints a
separate oracle bearer token once to its private startup stderr. Keep it in the
test runner/operator context, outside browser pages, model context, recordings and
published logs. The fixture does not log individual requests. Stop it with Ctrl-C.

Inject acknowledgement loss on the first new autosave or submit commit:

```sh
npm run dev:mobile-browser-fixture -- --drop-response-after-commit autosave
npm run dev:mobile-browser-fixture -- --drop-response-after-commit submit
```

Run these commands separately with a fresh server for each scenario. A fault is
armed once per fixture instance, for the selected operation kind. It closes the
HTTP response **after** the document and operation record have changed. An exact
replay is not another commit and does not re-arm the fault.

The default listener is loopback. `--host`, `--port` and `--max-operations` are
explicit test options; `--port 0` selects an available port. For a physical device,
bind to a specific reachable address on a controlled test network and use exactly
the printed host in the URL. Do not use `0.0.0.0` as a browser destination: the
fixture checks Host against its configured address. There is no public deployment
or production service in this change.

## Pages and API

| Path | Purpose |
| --- | --- |
| `/` | Task and synthetic account selection. |
| `/sources/one` | Fictional workshop schedule, room and capacity. |
| `/sources/two` | Fictional participant preferences and brief requirements. |
| `/drafts/alpha/draft-a` | First draft and autosaving form. |
| `/drafts/beta/draft-b` | Second synthetic document, useful for identity-mismatch tests. |
| `GET /api/documents/<account>/<document>` | Public synthetic document state and this fixture's run ID. |
| `POST /api/operations` | One exact JSON autosave or submit operation. |
| `GET /oracle` | Bearer-protected, read-only operation ledger, documents, limits and fault state. |

Normal fixture pages and operations are unauthenticated synthetic test data. The
account labels are identity fields, not production tenancy or access control.
The oracle is separate from page-reported success but resides in the same server
process. It is authoritative fixture readback, not independent-process containment,
production permission enforcement or a signed receipt system.

An operation has exactly these fields:

```json
{
  "fixtureId": "<32 hex characters from this running fixture>",
  "operationId": "<unique ID retained for this exact attempt>",
  "kind": "autosave",
  "accountId": "alpha",
  "documentId": "draft-a",
  "baseRevision": 0,
  "payload": {
    "title": "Workshop brief",
    "notes": "Synthetic task content"
  }
}
```

The server binds an accepted operation ID to the exact run, kind, account,
document, base revision, title and notes. Object key order is immaterial; string
values are not normalized. Lookup of an already accepted ID precedes current
revision and capacity checks. Consequently an exact replay returns its original
receipt, even after later document changes. Reusing the ID with changed bound
fields returns a conflict. A new stale operation is refused without a commit.

The first accepted operation increments the document revision. Autosave and
submission have separate counters. Submission marks the document final; a new
mutation then fails. Accepted records are never evicted to make room for another
mutation. Defaults are 128 accepted operations across the instance, an 8,192-byte
request body, a 120-code-unit title and 2,000-code-unit notes. `--max-operations`
accepts 1 through 1,000. Connection and request limits are also bounded.

**All state and replay guarantees last only for one running fixture instance.**
Restart creates a new run ID and empty state. A request from an old run is refused.
This is not the durable task or effect journal used by the eventual assistant.

## Client behavior and selectors

The served `client.js` is the client tested by the Node VM harness. Both `#title`
and `#notes` listen to `input`, so the existing native driver's emitted input event
triggers autosave. Consecutive edits are serialized and coalesced to the latest
pending values. Immediate submission waits for pending autosaves, then submits
the saved values. It cannot race a pending autosave with a new submission.

Before dispatch, the client stores the exact operation in `sessionStorage`.
It checks the acknowledgement against that operation before advancing its local
revision. A missing, interrupted, unreadable or mismatched acknowledgement sets
`#status[data-state="unknown"]`, disables changes and retains the original ID.
Reload with retained pending state remains unknown and sends no mutation. There
is no automatic retry or fresh-ID recovery. Known refusals stop the form too.

If secure random ID generation or pending-state storage is unavailable, the
client blocks before dispatch. Its random IDs use `crypto.getRandomValues`, which
does not depend on the secure-context-only `randomUUID` method. See the
[Web Cryptography interface](https://www.w3.org/TR/webcrypto/#crypto-interface).

Stable selectors include `#source-one`, `#source-two`, `#draft-form`, `#title`,
`#notes`, `#submit-button`, `#status`, `#revision`, `#operation` and `#receipt`.
Observe the asynchronous status and provider state after `typeText`; completion
of the native JavaScript call alone does not prove an autosave acknowledgement.

`sessionStorage` supports the page-reload scenario tested here. It is not a
guarantee across tab destruction, app termination, storage loss or device changes.
Native durable recovery must retain unresolved operation identity separately.

## Separate provider readback

The browser must not receive the oracle token. Tests can retain it from the
programmatic API and query the oracle separately:

```js
import assert from 'node:assert/strict';
import { startFixture } from './scripts/mobile-browser-fixture/server.mjs';

const fixture = await startFixture({ port: 0 });
try {
  const response = await fetch(`${fixture.url}/oracle`, {
    headers: { Authorization: `Bearer ${fixture.oracleToken}` }
  });
  assert.equal(response.status, 200);
  const oracle = await response.json();
  assert.equal(oracle.operations.length, 0);
} finally {
  await fixture.close();
}
```

`startFixture` returns `{ url, fixtureId, oracleToken, close }`. Options are
`host`, `port`, `maxOperations`, `dropResponseAfterCommit` and an optional
test-supplied `oracleToken`. The defaults generate a fresh run ID and random token.
The close function shuts down active connections and may be called more than once.

The oracle accepts only GET with its bearer credential. There is no reset, mutate
or fault-arm endpoint. Fault selection is startup configuration, outside the
page's control. Request Host and mutation Origin are checked; permissive CORS is
not enabled. These controls protect a bounded local test fixture, not arbitrary
websites operated by an agent.

## Qualification scenarios

| Scenario | Required observation |
| --- | --- |
| Read and compose | Extract both real pages. The brief includes Tuesday at 10:00, Room Delta, aisle-seat and decaf preferences, and stays below eighty words. Twelve seats is available supporting detail. |
| Autosave before submit | Type into the form. The separate ledger records an autosave and changed document while submission count remains zero. |
| Immediate submit | Request submit while an autosave is pending. The final submitted payload contains the latest typed values, with the autosave acknowledged first. |
| Stale page | Load the same draft twice; change it through one page. The old page's new operation is refused, with no extra provider mutation. |
| Lost autosave response | Start the autosave fault. The page retains UNKNOWN and the same ID after reload. The oracle records one committed autosave. |
| Lost submit response | Start the submit fault. The page retains UNKNOWN; the oracle records one final submission. |
| Exact replay | A privileged test harness explicitly resends the identical operation. It receives the original receipt and the ledger remains unchanged. The page itself never does this. |
| Identity conflict | Change a bound field while retaining an accepted ID. Refusal leaves the original record and document intact. |
| Capacity and isolation | Exhaust an instance's bounded records; confirm refusal without eviction. A separate instance remains separate and rejects the old run ID. |

The included tests execute actual loopback HTTP and the actual client script with
a minimal DOM/storage/event harness. They cover server semantics and client
control flow. They do not implement a browser, CSS layout, WebKit navigation,
native approvals, iOS storage/lifecycle behavior or real account authorization.

## Next native qualification

The native implementation and device evidence are tracked separately in
[#210](https://github.com/advatar/Browser/issues/210).

The existing application implementation is
[`BrowserWebView.swift`](../../swift/dBrowser/dBrowser/BrowserWebView.swift), wired
through [`ContentView.swift`](../../swift/dBrowser/dBrowser/ContentView.swift) and
[`BrowserViewModel.swift`](../../swift/dBrowser/dBrowser/BrowserViewModel.swift).
It already has UIKit and AppKit hosts. Its current page snapshot is structured
DOM data; the driver does not yet implement screenshot capture, separate
per-agent website data stores, or explicit upload/download integration.

The shortest new native test should mount that real UIKit view with its real
view-model callbacks, navigate to a fixture source, invoke `requestDOMQuery` and
`requestPageSnapshot`, and await the coordinator's actual result. Then exercise
`requestDOMAction`/the existing approval path for typing and inspect the separate
provider ledger. Do not replace native callbacks with fabricated results or copy
the driver's JavaScript into a test-only browser implementation.

### Prepared Mac prerequisites

The project is `swift/dBrowser/dBrowser.xcodeproj`, with targets `dBrowser`,
`dBrowserTests` and `dBrowserUITests`. The source baseline declares iOS 26.4.
No shared scheme is checked in; discover the available scheme first. The existing
README uses `dBrowser` and records macOS commands, not an iOS qualification result.

Restore the local package references relative to `swift/dBrowser`:

- `../../../Packages/UniversalInteractionKit`
- `../../../Packages/UniversalInteractionKit/Packages/UniversalA2UI`
- `../../../ZeroK/zk-llm-gateway/zk-llm-gateway-swift-sdk`

These sibling packages are absent in the current fixture implementation workspace.
An installed compatible Xcode/iOS SDK, eligible simulator and suitable signing for
a physical iPhone are also required. The following are **commands to run on that
prepared Mac**, not recorded successes:

```sh
xcodebuild -list -project swift/dBrowser/dBrowser.xcodeproj
xcodebuild -showdestinations \
  -project swift/dBrowser/dBrowser.xcodeproj \
  -scheme dBrowser

xcodebuild build \
  -project swift/dBrowser/dBrowser.xcodeproj \
  -scheme dBrowser \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>'

xcodebuild test \
  -project swift/dBrowser/dBrowser.xcodeproj \
  -scheme dBrowser \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:dBrowserTests
```

The current test targets contain no fixture-specific native integration test.
Running them cannot substitute for adding and running the test described above.
For a provisioned physical iPhone, select `platform=iOS,id=<DEVICE_UDID>` instead.
Record the actual device, OS, source revision, fixture configuration, native events
and separately collected outcome evidence.

`127.0.0.1` on an iPhone refers to the phone, not the development Mac. Physical
device connectivity needs a deliberately configured reachable test host. The
current app plist allows ATS local networking but has no
`NSLocalNetworkUsageDescription`; qualify local-network permission and a suitable
purpose string in the native follow-up. Do not add broad ATS exceptions to make
this fixture appear qualified.

After the positive native test, exercise stale document/grant invalidation,
content-process termination, app suspension/relaunch and retained unknown
outcomes. iOS may suspend an app; these Node tests establish no continuously
running browser guarantee. See [Apple's background execution
sequence](https://developer.apple.com/documentation/UIKit/about-the-background-execution-sequence)
and [WebKit content-process termination callback](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate(_:)).
