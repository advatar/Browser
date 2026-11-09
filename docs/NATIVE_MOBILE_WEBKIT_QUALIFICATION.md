# Native mobile WebKit qualification candidate

Related work: [Browser #210](https://github.com/advatar/Browser/issues/210),
stacked on [PR #211](https://github.com/advatar/Browser/pull/211) at
`a1d98bb64418360ac5e28641014637fdc46341db`.

## Mac execution — 9 November 2026

A subsequent physical run at clean commit `9f4c5ad43082eb74abf3bd5649c301f98ff7a913`
passed all five scenarios, each with one pass, zero failures and zero skips,
followed by host oracle readback. Ajfån is an iPhone 15 Pro running iOS 27.0.1
(24A446). Xcode 27.2 built with team `L2AF8KFX35`, Apple Development identity
`CR7TA84P3G`, and the existing dBrowser provisioning profile. The user enabled
local-network permission after an earlier request failed with “Local network
prohibited”; the successful LAN readbacks establish connectivity with the Mac
firewall enabled. The private logs, result bundles, provider readbacks, source
and dependency identities are retained at
`~/dev/advatar/qualification-artifacts/browser-pr212-device-pass-20261109`.
The previous locked and permission-denied attempts remain preserved.

PR head `9e921e2f3087c11652e8c4e102701bef118309ea` was tested with the
scoped source diff retained in the private evidence directory. Xcode 27.2
(27B52), iOS Simulator 27.0 (24A434), Node 26.10.0: the hosted test build
and all five scenarios passed on iPhone 18 Pro, each with one pass and no
failures or skips, followed by host oracle readback. The Node suite passed 24/24.

The initial build exposed manual build ordering, an uninitialized blst gitlink,
missing test imports and a pre-existing test actor-isolation failure. The scheme
and test compilation fixes are included here. The exact logs are retained. The
local UIK worktree was clean at `41f8d982f9b49b1c2fa52f5aa600752d99c22370`,
matching the checked-in A2UI pin; the clean ZeroK SDK was at
`555092ca1dd222803953b095d9a7f176f2743bc7`, and blst at
`d29fef46c29a662ec215a9eeb9578e25f9146b6d`.

The signed physical iPhone 15 Pro build succeeded with team `L2AF8KFX35`.
Xcode could not launch tests because “Unlock Ajfån to Continue”; the waiting
run was interrupted. No physical test or permission outcome is claimed. Unlock
and keep the phone awake, then rerun the device command and allow local-network
access and firewall connections if prompted. Private logs, xcresults, oracle
readbacks, metadata and tested diff are retained under
`~/dev/advatar/qualification-artifacts/browser-pr212-20261109`.

## Evidence status — 7 November 2026

This increment supplies hosted iOS integration tests, a shared Xcode scheme and
an orchestration command. **Native compilation and execution are unverified.**
The implementation workspace is Linux x86_64, without `swift`, `xcodebuild`,
an iOS simulator, the required sibling packages or an accessible eligible iPhone.
No simulator or physical-device pass is claimed. Nothing has been pushed,
merged or deployed; publication requires the user's explicit approval.

| Check | Observed result |
| --- | --- |
| Existing fixture plus runner Node tests, Node v24.22.1 | 24 passed, 0 failed, 0 skipped (21 existing + 3 new) |
| Fixture/client and runner JavaScript syntax | Passed |
| Native Swift source grammar parser | Passed; not Swift type checking or SDK compilation |
| Shared scheme XML and app plist parsing | Passed |
| Native runner preflight on this host | Correctly refuses: compatible macOS/Xcode required |
| iOS simulator build and five hosted scenarios | Unexecuted |
| Physical iPhone build and five hosted scenarios | Unexecuted |
| Repository-wide CI | Not claimed; existing legacy failures remain separate |

The earlier legacy failures recorded on PR #211 concern Rust formatting,
yanked `core2 0.4.0` through `libipld`, and the frontend npm-ci lockfile
requirement. Those paths are unchanged. STATUS also records a historical
actor-isolation compile failure in the existing `dBrowserTests.swift`; its
current Apple-toolchain status has not been re-established here. The shared
scheme selects only the new tests for execution but still compiles the existing
test target. If that build fails, preserve the diagnostic as a separate blocker;
do not count this suite as passing or silently omit a scenario.

## What the native tests actually do

`swift/dBrowser/dBrowserTests/NativeMobileBrowserTests.swift` creates a foreground
`UIWindow`, mounts a `UIHostingController` containing the production
`BrowserWebView`, and observes the real `WKWebView` and coordinator. The SwiftUI
bindings and callbacks follow `ContentView`: model navigation updates, automation
results and one-time dispatch ownership all use production code. Stores are
otherwise ephemeral for test isolation. Use a dedicated simulator/test app
installation; this is not a test to run over personal browsing state.

No test-created browser result, copied browser JavaScript or replacement WebKit
driver supplies a positive result. Tool *inputs* are created by the production
`CopilotToolProposalFactory` and introduced through the existing conversation
restoration path, then approved with `approveToolProposal`. This intentionally
does not exercise a live LLM router. `requestDOMQuery`, `requestPageSnapshot` and
`requestDOMAction` also run through the existing model. Tests disable ad blocking
to isolate browser execution; ad-blocking behavior is outside this increment.

| Hosted test | Required native and provider evidence |
| --- | --- |
| NavigationAndAutosaveBeforeSubmit | Actual decoded heading/snapshots from both sources; focus; approved typing; asynchronous saved state; matching operation ID; authoritative autosave count 1 and submission count 0 before approved submit; final ledger order autosave then submit. |
| StaleDocumentRefusal | Two mounted real pages initially at revision 0; one commits; the other's stale operation is refused, controls lock, ledger stays unchanged and refused ID is absent. |
| NavigationInvalidatesApprovalAndDispatch | Same-URL reload invalidates snapshot and proposal; cross-document navigation invalidates a held approved dispatch; replay through the real coordinator cannot claim it; a live request with a mismatched generation produces a real failed callback; a fresh beta-page action supplies a positive control. |
| LostAutosaveAcknowledgement | After-commit response loss; page UNKNOWN; oracle confirms exact original operation and receipt; reload retains ID; consumed approval cannot reissue; programmatic input/submit probes cannot create a new provider operation. |
| LostSubmitAcknowledgement | Same uncertainty/recovery checks with exactly one autosave and one final submission. |

The lost-ack checks repeatedly read the ledger for more than the fixture's five
second fetch timeout. They do not prove absence of retries for unlimited time.
Normal autosave is explicitly awaited before submit in this suite. The fixture's
immediate-submit-while-saving ordering remains Node-tested; deterministic native
race injection is a separate follow-up.

## Run on a prepared Mac

Required: Node 24, compatible Xcode and iOS SDK, a foreground eligible iOS 26.4+
simulator (the project deployment target is 26.4), and the existing local packages:

- `../Packages/UniversalInteractionKit`, relative to the Browser repository root.
- `../Packages/UniversalInteractionKit/Packages/UniversalA2UI`.
- `../ZeroK/zk-llm-gateway/zk-llm-gateway-swift-sdk`.

Restore those authenticated repositories at their intended revisions. The runner
records their Git revisions and dirty state; do not treat unreviewed dependency
changes as part of this Browser qualification. The existing remote Swift package
resolution must also succeed. The runner does not rewrite package references,
install Xcode, change signing teams or enable provisioning automatically.

```sh
npm run test:mobile-browser-native -- --preflight
xcrun simctl list devices available
npm run test:mobile-browser-native -- \
  --destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>'
```

The preflight shows schemes and destinations. Use the checked-in
`NativeMobileBrowser` scheme. Keep the app foregrounded and unlock the simulator.
A missing foreground scene is a failure, not a hidden headless/mock fallback.

`run-native.mjs` builds once using isolated DerivedData, then launches each method
serially with its own fresh fixture imported from `server.mjs`. The existing
fixture pages, client and server are unchanged. The two fault cases select the
existing startup-only lost-ack option. No external service or real user account
is involved. Simulator signing is disabled for the build only.

An absent fixture configuration causes these tests to skip in ordinary test
runs. The dedicated runner sets the required configuration and accepts a scenario
only if `xcresulttool get test-results summary` reports exactly one passing test,
zero failures and zero skips. A missing/changed result schema fails closed.

## Physical iPhone extension

Use a provisioned dedicated development installation, Developer Mode, an unlocked
and trusted connected iPhone with a compatible OS, and a reachable controlled LAN
address **belonging to the Mac running the fixture**. The phone's loopback is not
the Mac's loopback. Do not use a wildcard host, public tunnel or public deployment.
Allow the macOS firewall connection and the app's local-network permission when
prompted. This change supplies `NSLocalNetworkUsageDescription` and retains the
existing `NSAllowsLocalNetworking`; it adds no broad ATS bypass.

```sh
xcrun devicectl list devices
npm run test:mobile-browser-native -- \
  --destination 'platform=iOS,id=<DEVICE_UDID>' \
  --host '<MAC_LAN_IP>' \
  --team '<EXISTING_PROVISIONED_TEAM_ID>'
```

The optional team selects an existing signing configuration; the runner does not
pass `-allowProvisioningUpdates`. If local-network or ATS behavior blocks the
explicit HTTP fixture address, record it and fix the scoped configuration before
claiming qualification. Do not bypass it with `NSAllowsArbitraryLoads`.

For device qualification retain the exact device model/identifier, OS version and
build, Xcode build and SDK, source commit/dirty diff identity, resolved package
revisions, destination, fixture host/run IDs/faults, signing configuration and
permission/firewall state. The runner records toolchain, source/dependency
identity, destination and fixture configuration; native attachments record
`UIDevice` and `ProcessInfo` software data plus real navigation/action callbacks.
The xcresult device/configuration summary supplies additional device details.
Manually record the signing, local-network permission and firewall observations.
No physical-device record exists for this Linux implementation session.

## Credential and evidence boundary

Only the Node orchestrator and private XCTest oracle instrumentation receive the
oracle credential. The orchestrator passes it as a `TEST_RUNNER_` environment
variable. It is never included in a page URL, DOM, WKWebView configuration,
JavaScript, browser model, conversation, model request, cookie or screenshot.
The Swift reader uses a separate ephemeral `URLSession`, GET only, rejects
redirects, and fails if the actual configured fault differs from the scenario.
The Node runner performs another authenticated GET after each native pass.

The oracle is authoritative **fixture** state in the same server process; it is
not an independent production authority. Page UNKNOWN and native DOM-action
success remain distinct from verified provider commitment. The verifier does
not clear page uncertainty or authorize a new operation. The entire original
operation binding is compared with the oracle receipt.

Results live in a newly created private mode-0700 directory outside the repo:
`qualification.json`, redacted text logs, raw `.xcresult` bundles and host oracle
JSON. Raw diagnostic bundles can contain test environment data: keep them private
and do not upload them. Only deliberately inspected exports of the synthetic
ledger, native callbacks and platform facts should be shared. Text logs redact
the token. No token is printed by the orchestrator and it does not invoke the
fixture CLI that prints a startup credential. Stopping the fixture invalidates
that run's credential and state. This is test-runner isolation, not a secret store
or a security boundary against compromised code in the test process.

## Remaining BrIAn and Kline work

1. Run and review this suite on simulator, then a real iPhone; preserve failures
   and exact evidence. Establish reproducible local/remote package resolution
   before adding a native CI job. A shared scheme alone does not solve dependencies.
2. Bind a BrIAn foreground browser capability to Kline's actual assignment,
   generation, authority and action-journal identity. These tests seed tool input;
   they do not qualify router transport, mobile App Intents or multi-agent scheduling.
3. Treat typing as effectful: this fixture autosaves on input. The generic native
   `typeText` policy currently asks approval only for credential-like fields.
   The tests explicitly use approved tool proposals; that does not repair or prove
   universal effect classification for arbitrary websites. Integrate pre-dispatch
   authority for all potentially mutating inputs and page-triggered network work.
4. Distinguish DOM dispatch success from effect settlement in the assistant's UI
   and journal. A native `.success` for typing/submit currently means JavaScript
   returned. Page UNKNOWN/provider-committed is established only by separate
   fixture readback here. Bind durable recovery to the full original operation,
   retain UNKNOWN when verification is unavailable, and prohibit fresh-ID retry.
5. Add durable app/tab/content-process crash recovery and cross-device continuation.
   Current fixture `sessionStorage` coverage is same-tab reload only. No background
   execution or app-termination guarantee is established.
6. Add per-agent website data stores, identity/tenant isolation, concurrent ownership
   and cancellation tests. These two page instances use the default WebKit store;
   they demonstrate stale revisions, not profile or agent isolation.
7. Qualify actual waiting/polling (`waitForSelector` is currently an immediate
   query), screenshots, upload/download and authenticated login/MFA handoffs.
   Navigation policy is not complete interception of page-controlled requests.

## Review and publication

Review the local diff on `feat/210-native-webkit-qualification`, based on #211.
The only application configuration change is the local-network purpose string;
there is no driver or authorization-policy behavior change in this increment.
After explicit approval, push this branch and open a stacked draft PR targeting
`feat/209-mobile-browser-fixture`. If #211 merges first, rebase onto its merged
source and rerun relevant checks. Do not duplicate or replace its fixture. Do not
merge, deploy or label native qualification complete until the missing Apple
execution evidence has been reviewed.
