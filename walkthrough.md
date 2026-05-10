# dBrowser — Complete UX & Usability Review

> **Scope**: Full-stack review of the Decentralized Web Browser (`orbit-shell-ui` React frontend + `crates/gui` Rust/Tauri backend), covering information architecture, interaction design, visual design, accessibility, performance, and code quality as they affect end-user experience.

---

## Executive Summary

dBrowser is an ambitious project: a privacy-first desktop browser with embedded IPFS/IPNS/ENS support, an AI copilot, and full wallet integration — all built on Rust + Tauri + React. The architecture is sound and the feature set is impressive. However, **the current UX has several gaps that would block real adoption**, ranging from missing feedback loops and dead controls to a copilot panel that conflates power-user configuration with everyday use. This review identifies **42 findings** organized by severity and component.

---

## 1. Overall Information Architecture

### 1.1 Layout Structure

```
┌──────────────────────────────────────────────────────┐
│  TabBar (40px)                                   [+] │
├──────────────────────────────────────────────────────┤
│  NavigationBar (48px)  [← → ↻ ⌂] [URL Bar] [🛡…⚙]  │
├────────┬─────────────────────────────────────────────┤
│Sidebar │  ContentArea                          (Co-  │
│ (320px │  (native webview position synced       pilot │
│  or    │   via set_content_bounds)              460px)│
│  48px  │                                             │
│collapsed│                                            │
├────────┴─────────────────────────────────────────────┤
│  StatusBar (28px)                                    │
└──────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> The layout follows a standard browser chrome pattern which is good for learnability. But the **simultaneous sidebar + copilot panel** can squeeze the content area to < 700px on a 1440px display — uncomfortable for actual browsing.

### 1.2 Navigation Model

| Surface | Access Method | Keyboard | Status |
|---------|--------------|----------|--------|
| URL bar | Always visible | `⌘L` | ✅ Good |
| Command palette | `⌘K` | ✅ | ✅ Good |
| Back/Forward/Reload | Toolbar buttons | ❌ No shortcuts | ⚠️ Missing |
| Tab management | Click + context menu | ❌ No `⌘T/W` | ⚠️ Missing |
| Sidebar sections | Click sidebar icons | ❌ No shortcuts | ⚠️ Missing |
| Settings | Dialog via toolbar | ❌ No `⌘,` | ⚠️ Missing |
| Copilot | Toolbar sparkle icon | ❌ No shortcut | ⚠️ Missing |

---

## 2. Component-Level Findings

### 2.1 Tab Bar

| # | Severity | Finding |
|---|----------|---------|
| 1 | 🔴 High | **No keyboard shortcuts for tab management.** Standard browser keybindings (`⌘T` new tab, `⌘W` close tab, `⌃Tab` cycle tabs) are completely absent. Only `⌘K` and `⌘L` are bound. |
| 2 | 🟡 Medium | **Closing the last tab leaves the user with "No active tab" — no auto-creation of a new tab.** In every major browser, closing the last tab either creates a new blank tab or closes the window. |
| 3 | 🟡 Medium | **Tab drag-and-drop reorder has no visual drop indicator.** The tab becomes 50% opacity during drag, but there's no insertion line or ghost preview at the drop target. |
| 4 | 🟢 Low | **Minimum tab width (180px) is generous but not adaptive.** With 8+ tabs, tabs overflow via `overflow-x-auto` with hidden scrollbar (`scrollbar-none`), making it impossible to know there are hidden tabs. |
| 5 | 🟢 Low | **Tab active indicator is a 2px bottom bar.** Works but is very subtle — could be missed on lower-contrast displays. |

### 2.2 Navigation Bar

| # | Severity | Finding |
|---|----------|---------|
| 6 | 🔴 High | **Security indicator is always hardcoded to `"secure"`.** The `SecurityIndicator` component receives `level="secure"` as a static prop — it never reflects the actual connection state (`<SecurityIndicator level="secure" />`). This is actively misleading. |
| 7 | 🔴 High | **Developer Tools button is non-functional.** The `<Code>` icon button has no `onClick` handler — it renders but does nothing. Dead controls erode user trust. |
| 8 | 🟡 Medium | **URL bar uses `rounded-pill` class that doesn't exist in the design system.** Falls back to the default border-radius. Not a runtime error, but the URL bar has sharp corners instead of the intended pill shape. |
| 9 | 🟡 Medium | **Theme toggle cycles through 3 states (system → light → dark) but shows only 2 icons.** When in "system" mode, it shows the moon icon (same as light), so users can't tell which state they're in without the tooltip. |
| 10 | 🟡 Medium | **Wallet button label says "Connect Wallet" / "Disconnect Wallet" but there's no wallet selection UI.** No flow to choose which wallet to connect, view balance details, switch networks, or see transaction history inline. |
| 11 | 🟢 Low | **Excessive `TooltipProvider` wrapping.** Each button wraps its own `<TooltipProvider>` (9 instances in NavigationBar alone). This should be a single provider at the app level. While not a visible bug, it creates unnecessary React context nesting. |

### 2.3 Sidebar

| # | Severity | Finding |
|---|----------|---------|
| 12 | 🟡 Medium | **No search available for Downloads section.** Bookmarks and History have search inputs, but Downloads does not — inconsistent pattern. |
| 13 | 🟡 Medium | **Bookmark "Edit" context menu item is a dead button.** The `ContextMenuItem` for "Edit" in BookmarkList has no `onClick` handler. |
| 14 | 🟡 Medium | **Bookmarks are local-only (Zustand in-memory) with no persistence.** The store doesn't sync bookmarks to the Tauri backend or disk. Closing the app loses all bookmarks. Downloads and History are synced, but bookmarks are not. |
| 15 | 🟢 Low | **Download progress shows 0% for indeterminate downloads.** When `total_bytes` is null (chunked transfer), `progress` evaluates to 0, and the `<Progress>` bar sits at 0 even though bytes are being received. |
| 16 | 🟢 Low | **Sidebar collapse/expand has no transition animation.** Goes from 320px to 48px instantly, causing content to jump. |

### 2.4 Content Area

| # | Severity | Finding |
|---|----------|---------|
| 17 | 🔴 High | **Loading indicator is indeterminate only.** The pulsing gradient bar (`animate-pulse`) gives no sense of progress. There's no percentage, no determinate progress bar, and no timeout feedback for slow-loading content. |
| 18 | 🟡 Medium | **Error states for failed page loads are missing.** If `activate_tab_webview` or `set_content_bounds` fails, errors are logged to console but no user-facing error page or retry mechanism appears. |
| 19 | 🟡 Medium | **Magic numbers for content bounds alignment.** The `ContentArea` uses hardcoded offsets (`HORIZONTAL_OVERSCAN = 8`, `HORIZONTAL_SHIFT = 10`, `VERTICAL_OFFSET = 8`, etc.) to position native webviews. These are fragile and will break on different display scales or when the surrounding chrome layout changes. |

### 2.5 Home Page

| # | Severity | Finding |
|---|----------|---------|
| 20 | 🟡 Medium | **Curated links may all be unreachable, leaving a blank homepage.** The `HomePage` probes each curated URL via `probe_runtime_url`. If the IPFS node isn't running or ENS resolution fails, the user sees "No curated decentralized entries are reachable right now" — with no regular web shortcuts, no search bar, no recent history tiles. The homepage becomes useless for everyday use. |
| 21 | 🟡 Medium | **"Checking decentralized starters..." has no timeout or skeleton UI.** The availability check runs N sequential probes. If the embedded node is slow, the user stares at a plain text message for potentially 10-30 seconds with no loading indicator. |

### 2.6 Status Bar

| # | Severity | Finding |
|---|----------|---------|
| 22 | 🔴 High | **StatusBar shows hardcoded "Demo status · Mock connected" in production.** This was clearly a development placeholder that was never replaced. Users will see this and assume the product is unfinished. |
| 23 | 🟡 Medium | **StatusBar ignores the `backendConnected` prop entirely.** The `StatusBar` component accepts `backendConnected` via App but its internal implementation doesn't use it — the signature doesn't even include it (`function StatusBar()` with no props destructuring). |
| 24 | 🟡 Medium | **IPFS content indicator uses a naive string check.** `isIpfs` checks if `activeTab?.url?.toLowerCase().includes('ipfs')` — this would match any URL containing "ipfs" in the path or query, like `https://example.com/docs/ipfs-tutorial`. |

### 2.7 Settings Dialog

| # | Severity | Finding |
|---|----------|---------|
| 25 | 🟡 Medium | **No "Save" button — settings auto-save on every keystroke.** Each character typed in the Home Page or IPFS Gateway field triggers `updateSettings` → `tauriInvoke('update_settings', ...)`. This means every letter fires a backend round-trip. Should debounce or use explicit save. |
| 26 | 🟡 Medium | **Settings changes take effect immediately but have no undo or revert.** There's no "Reset to defaults" button and no confirmation when making significant changes (like changing the ENS resolver or enabling Tor). |
| 27 | 🟢 Low | **The Tor toggle has no status feedback.** Enabling Tor routing is a significant action — users should see whether Tor is actually connected, its circuit status, and estimated latency impact. |

### 2.8 Command Palette

| # | Severity | Finding |
|---|----------|---------|
| 28 | 🟡 Medium | **"Settings" command in the palette logs to console instead of opening the dialog.** Line 108: `console.log('Open settings')` — it doesn't actually open the settings dialog. |
| 29 | 🟢 Low | **Keyboard navigation works with arrows but Enter doesn't differentiate between URL submission and command execution.** If filtered commands exist AND the query looks like a URL, the URL takes precedence, meaning you can't use command palette to navigate to `settings.eth` (it'll try to navigate instead of executing a command). |

### 2.9 Site Info Dialog

| # | Severity | Finding |
|---|----------|---------|
| 30 | 🟡 Medium | **Site info is almost entirely derived client-side with mock data.** The dialog shows domain + protocol parsed from URL, and cookie count from `siteInfo` which is `null` by default and never populated. TLS certificate details, tracker counts, and actual security auditing are absent. |

### 2.10 Copilot Panel (AI Agent)

| # | Severity | Finding |
|---|----------|---------|
| 31 | 🔴 High | **The panel is 1,143 lines in a single component with no decomposition.** `CopilotPanel.tsx` manages 17+ state variables, 10+ async operations, 5 major sections (Task, Credits, Apps, Schedules, Runs), and inline event subscriptions — all in one function component. This is unmaintainable and hurts iteration speed. |
| 32 | 🔴 High | **Agent approval uses `window.confirm()` — a blocking browser dialog.** When the agent requests a capability approval, it fires `window.confirm(...)` which blocks the entire UI thread. This is hostile UX and prevents the user from inspecting what the agent is doing before approving. |
| 33 | 🟡 Medium | **No conversational interface.** The copilot is a task runner, not a chat. Users describe a task in a textarea and get a structured result. This is fine for power users but doesn't match the "copilot" mental model that users expect (a back-and-forth conversation with context). |
| 34 | 🟡 Medium | **Run details show raw JSON for tool arguments and observations.** The `<pre>` blocks dump `JSON.stringify(step.Tool.call.arguments, null, 2)` — this is developer output, not user-facing content. |
| 35 | 🟡 Medium | **"Top up 10k" credits button has no explanation of what tokens cost.** There's no pricing info, no confirmation, and no link to understand the credit system. |

---

## 3. Cross-Cutting Concerns

### 3.1 Accessibility

| # | Severity | Finding |
|---|----------|---------|
| 36 | 🔴 High | **No keyboard shortcut documentation or discovery.** The two working shortcuts (`⌘K`, `⌘L`) are undiscoverable — no help dialog, no shortcut hints in menus, no onboarding. |
| 37 | 🟡 Medium | **Tab bar items lack proper ARIA roles.** Tabs are plain `<div>` elements with `onClick` — they should be `role="tab"` inside a `role="tablist"` with `aria-selected`. Screen readers cannot interpret the tab bar. |
| 38 | 🟡 Medium | **Focus management on tab close is visual-only.** When closing a tab, the next tab becomes "active" in state but DOM focus isn't managed. Keyboard users lose their focus position. |

### 3.2 Performance

| # | Severity | Finding |
|---|----------|---------|
| 39 | 🟡 Medium | **Settings updates fire full backend sync on every keypress.** As noted in §2.7, this is wasteful. Should debounce by ~500ms or use explicit save. |
| 40 | 🟢 Low | **History and Downloads re-render on every store change.** The Zustand store lacks selector optimization — components subscribe to the entire store slice rather than individual fields. |

### 3.3 Dead / Leftover Code

| # | Severity | Finding |
|---|----------|---------|
| 41 | 🟡 Medium | **`App.css` contains leftover Vite scaffold styles.** The `.logo`, `.card`, `.read-the-docs`, and `@keyframes logo-spin` styles are from the default Vite+React template and are completely unused. |
| 42 | 🟡 Medium | **`index.html` meta author is "Lovable"** — this is from the lovable.dev code generator and should be updated to the actual project author. The `lovable-tagger` dev dependency is also still in `package.json`. |

---

## 4. Severity Summary

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 High | 8 | Misleading security indicator, hardcoded demo text, dead controls, missing keyboard shortcuts, blocking `window.confirm`, unmaintainable copilot component |
| 🟡 Medium | 26 | Missing feedback, dead buttons, no persistence, no error states, layout issues |
| 🟢 Low | 8 | Visual polish, code hygiene, minor consistency issues |

---

## 5. Priority Recommendations

### P0 — Must Fix (ship blockers)

1. **Remove "Demo status · Mock connected" from StatusBar** and wire in real backend connection status
2. **Fix the hardcoded security indicator** — derive the actual security level from the active tab URL and TLS state
3. **Disable or properly implement the Developer Tools button** — don't show non-functional controls
4. **Add standard keyboard shortcuts** — at minimum `⌘T` (new tab), `⌘W` (close tab), `⌃Tab` / `⌃⇧Tab` (cycle), `⌘,` (settings)
5. **Replace `window.confirm()` for agent approvals** with an inline approval card in the copilot panel
6. **Fix the Settings command palette action** to actually open the settings dialog

### P1 — Should Fix (before public beta)

7. Auto-create a new tab when closing the last one
8. Add bookmark persistence (sync to backend or local storage)
9. Add debouncing to settings updates
10. Show a useful default homepage (recent history, frequent sites) instead of only IPFS curated links
11. Add loading skeletons to HomePage while checking availability
12. Add the `rounded-full` class to URL bar (intended pill shape)
13. Add ARIA roles (`tablist`, `tab`, `aria-selected`) to the tab bar
14. Split CopilotPanel into sub-components (TaskCard, CreditCard, AppList, RunList, RunDetail)
15. Add an error/crash page when navigation or webview creation fails

### P2 — Nice to Have (polish)

16. Add sidebar expand/collapse animation (CSS transition on width)
17. Add tab overflow indicators (scroll arrows or "show all tabs" dropdown)
18. Add drag-and-drop visual indicator for tab reorder
19. Clean up leftover scaffold code (`App.css`, Lovable metadata)
20. Add a keyboard shortcuts help dialog (`⌘/` or `?`)

---

## 6. Architecture Notes

### What Works Well
- **Rust/Tauri backend is well-structured** — clean separation of `browser_engine`, `protocol_handlers`, `security`, `wallet_store`, `telemetry`, and `agent` modules
- **The event bridge is solid** — real-time `browser://tab-state-updated`, `browser://downloads-updated`, and `browser://navigation-blocked` events provide a reactive frontend/backend sync
- **Native child webviews per tab** — proper isolation and page-load event handling
- **Navigation security policy** is enforced at the Rust level, not just advisory
- **Design system is thoughtful** — HSL-based tokens, light/dark mode, glass morphism utilities, consistent typography scale
- **The Zustand store is well-designed** — proper tab history tracking with back/forward/reload intents

### What Needs Work
- **The frontend was scaffolded by lovable.dev** and still carries scaffold artifacts — the codebase would benefit from a pass to remove template boilerplate
- **Two frontend directories exist** (`orbit-shell-ui` and `crates/gui/src/{main.ts, utils.ts, types.ts}`). The legacy frontend in `crates/gui/src` appears to be a separate system. This dual-frontend situation adds confusion
- **CopilotPanel is the single largest source of complexity** in the frontend (42KB, 1143 lines). It handles agent lifecycle, credit management, scheduling, live activity streaming, and run history — all inline. This needs decomposition before adding features
