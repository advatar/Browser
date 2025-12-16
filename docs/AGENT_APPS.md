# Agent Apps & OpenAI Apps Inspiration

OpenAI previewed its upcoming **Apps** experience during the Spring Update: GPT builders can now
package instructions, tools, knowledge packs, and UI layouts into a single shareable card. The
roadmap highlights a few traits that influenced Advatar's implementation:

- **Composable instructions** – each OpenAI App pins system guidance, data sources, and tool scopes
  so a one-tap launch feels deterministic. Apps can publish capability requirements (browser,
  code interpreter, retrieval) and reuse them every time the run starts.
- **Shareable profiles** – builders get a branded card (name, tagline, hero color, icon) plus quick
  prompts. Apps may be private, workspace scoped, or public links that open in ChatGPT or the iOS
  launcher.
- **Workflow-first UX** – instead of long chats, Apps bias toward repeatable tasks (briefs, meeting
  notes, onboarding flows) with minimal input and rich output formatting. They also document which
  actions/tools will run up front for trust + approvals.

## Advatar Implementation

To echo that experience locally we now ship **Agent Apps** inside the browser:

1. `configs/agent_apps.json` defines reusable flows (id, name, launches, quick prompts, template).
2. `AgentAppRegistry` (Rust) loads and exposes those manifests to the UI; launching an app produces a
   templated `AgentRunRequest` so the existing MCP/AFM-aware agent executes the workflow.
3. The toolbar gets an **Apps** button that opens a drawer with cards, quick prompts, and the latest
   run output – a lightweight mirror of OpenAI's App launcher but backed by our sandboxed agent.

Each App documents if it needs egress, which skills it prefers, and the persona/instructions it uses.
Teams can now build OpenAI-style shareable workflows entirely offline with MCP servers.
