[Download the step-by-step change request plan (Markdown)](sandbox:/mnt/data/Strawberry_Parity_Change_Request.md?_chatgptios_conversationID=685060f6-cb78-8004-8243-6d5fca61ae08&_chatgptios_messageID=0a3145a4-1c20-4ba7-8181-aeaa9a42aacf)  
[Download the current source code snapshot used for this analysis](sandbox:/mnt/data/Browser-main.zip?_chatgptios_conversationID=685060f6-cb78-8004-8243-6d5fca61ae08&_chatgptios_messageID=0a3145a4-1c20-4ba7-8181-aeaa9a42aacf)

Below is a quick “what I found in your repo” + the **P0 step sequence** (the full, junior-dev-friendly plan with code excerpts is in the markdown file).

## What Strawberry requires for parity (so we implement the right primitives)

Strawberry’s core promise is that the companion **“goes anywhere you would go”** in the browser (pagination, clicking into detail pages, etc.) because it *actually browses* like a user.  [oai_citation:0‡Strawberry](https://strawberrybrowser.com/use-cases/getting-started)  
It also emphasizes:
- **Approvals for important actions** + visible activity history and “stop/take over.”  [oai_citation:1‡Strawberry](https://strawberrybrowser.com/use-cases/getting-started)  
- **Workflows that can be saved, rerun, and scheduled**, plus “multiple agents in parallel” for briefs and data pulls.  [oai_citation:2‡Strawberry](https://strawberrybrowser.com/use-cases/operations)  
- **Smart History** (natural language recall of visited pages) with local storage of summaries.  [oai_citation:3‡Strawberry](https://strawberrybrowser.com/security)  
- **Credits only when AI acts** (browsing is free).  [oai_citation:4‡Strawberry](https://strawberrybrowser.com/pricing)  

That implies you need two hard technical primitives first:
1) reliable **tab → DOM readback**  
2) reliable **tab → UI actions** (click/type/scroll) that truly affect the real tab

## What your current code does today (with source evidence)

### 1) You already have “real tabs” as isolated native child webviews
You create content tabs as child webviews in Rust (`ensure_tab_webview`), and you already execute JS into them for history/stop:

```rust
// crates/gui/src/main.rs
window.add_child(
  WebviewBuilder::new(&label, initial_webview_url),
  LogicalPosition::new(0.0, 0.0),
  LogicalSize::new(0.0, 0.0),
)?;
...
webview.eval("history.back();")?;
webview.eval("window.stop();")?;
```

That’s a great foundation for Strawberry-like UI automation.

### 2) Agents exist, but DOM read + DOM actions are not wired to real tabs

**DOM query tool is currently a stub** (hard-blocks you from extraction & page understanding):

```rust
// crates/gui/src/agent/tools.rs
Err(McpToolError::Invocation(
  "DOM querying is not available for isolated native content webviews".into(),
))
```

**DOM actions in agent-core are logging-only** (they don’t change the page):

```rust
// crates/agent-core/src/dom.rs
pub fn execute(&mut self, action: DomAction) -> DomObservation {
  self.events.push(event.clone());
  DomObservation::new(event, format!("{} executed", action.description()))
}
```

So today, the agent can “think” it clicked/typed/scrolled, but nothing happens in the actual tab.

### 3) Credits exist, but they won’t decrement in your default model path
`MeteredModel` charges credits based on `LanguageModelResponse.usage.*`, but your Foundation model client returns `LanguageModelResponse::new(text)` with default/empty usage, so tokens are 0 and nothing is charged.

This breaks Strawberry’s “credits only when AI acts.”  [oai_citation:5‡Strawberry](https://strawberrybrowser.com/pricing)

## P0 Step-by-step sequence (the minimum to close the biggest Strawberry gaps)

This is the critical path. If you do nothing else, do this in order.

### Step 1 — Build a Webview Automation Bridge (request/response channel)
You need a way to **run JS in the content webview AND get JSON back**. `eval()` alone won’t return values.

Use the standard embedded-webview pattern: **inject a script + send results back via IPC** (Wry supports `window.ipc.postMessage(...)` when an IPC handler is configured).  [oai_citation:6‡Docs.rs](https://docs.rs/wry/latest/wry/struct.WebViewBuilder.html)  
Tauri child webviews also support `initialization_script` in practice (and this is a common way to inject into additional webviews).  [oai_citation:7‡GitHub](https://github.com/tauri-apps/tauri/issues/10298)

**Deliverable:** a Rust module that can do:
- `bridge.request(tab_id, js) -> Value` with timeout
- correlate replies by request_id (UUID)
- route messages per-webview/tab

### Step 2 — Implement `browser.dom_query` for real (replace stub)
Once the bridge works:
- implement `browser.dom_query` by running JS like:
  - querySelectorAll(selector)
  - return structured results (text, href, tag, ariaLabel, value)
- cap output size and enforce `limit`

This unlocks “Extractor Ella” type behaviors and page understanding.

### Step 3 — Make DOM actions actually control the real tab
Right now `agent-core`’s `dom_action` tool only logs.

Implement a **pluggable DOM executor**:
- keep agent-core capabilities/approvals/ledger
- swap the execution backend from “log only” → “Tauri webview automation”

**Deliverable:** `dom_action` click/type/scroll/navigate visibly affects the content webview.

This is the “Strawberry signature” capability (operating pages like a human).  [oai_citation:8‡Strawberry](https://strawberrybrowser.com/use-cases/getting-started)

### Step 4 — Add “page snapshot” (don’t rely only on CSS queries)
For Strawberry-like robustness, add a tool:
- `browser.page_snapshot` → `{ url, title, mainText, keyLinks, keyButtons, forms }`

This should be the default “read what’s in front of you” tool.

### Step 5 — Streaming activity + cancellation (“stop/take over”)
Strawberry emphasizes keeping users in the loop with activity history + ability to stop/take over.  [oai_citation:9‡Strawberry](https://strawberrybrowser.com/security)

Implement:
- `run_id` per agent run
- stream tool-call events live (emit `agent://run-event`)
- `cancel_agent_run(run_id)` (cancellation token checked between steps)

### Step 6 — Fix credit metering (so budgets work)
Credits must decrement for LLM calls:
- if provider doesn’t return token usage, implement a fallback estimator
- report `tokens_used_estimated` and `credits_spent` per run

This aligns with “credits only when AI acts” (browsing itself stays free).  [oai_citation:10‡Strawberry](https://strawberrybrowser.com/pricing)

---

## What’s in the attached Markdown
The attached `Strawberry_Parity_Change_Request.md` is the full junior-dev plan, including:
- exact file paths to edit in your repo
- a suggested module layout (bridge, executor, snapshot tool)
- acceptance criteria (“definition of done”) for P0/P1
- code excerpts from your current repo proving where the stubs/limits are
- a roadmap for workflows + scheduling + “parallel agents” (P1) matching Strawberry’s claims  [oai_citation:11‡Strawberry](https://strawberrybrowser.com/use-cases/operations)
- Smart History + local-first memory (P2) aligned with Strawberry’s Smart History description  [oai_citation:12‡Strawberry](https://strawberrybrowser.com/security)

If you want, I can also turn that plan into a **set of GitHub-style issues** (one per step, each with checklists + acceptance tests) using the same repo-specific file references.
