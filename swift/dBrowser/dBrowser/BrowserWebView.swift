import Foundation
import SwiftUI
import WebKit

#if os(macOS)
import AppKit

typealias BrowserViewRepresentable = NSViewRepresentable
#else
import UIKit

typealias BrowserViewRepresentable = UIViewRepresentable
#endif

struct BrowserModelLoadRevisionTracker {
    private(set) var lastHandledRevision: UInt64?

    mutating func shouldHandle(_ revision: UInt64) -> Bool {
        guard lastHandledRevision != revision else { return false }
        lastHandledRevision = revision
        return true
    }
}

struct BrowserWebView: BrowserViewRepresentable {
    @Binding var tab: BrowserTab
    let command: BrowserWebCommandRequest?
    let adBlockingMode: BrowserAdBlockingMode
    let automationRequest: BrowserAutomationRequest?
    let navigationGeneration: UInt64
    let onApprovedAutomationDispatch: (UUID, UUID) -> Bool
    let onNavigationUpdate: (BrowserNavigationUpdate) -> Void
    let onAutomationResult: (BrowserAutomationResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

#if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, context: context)
    }
#else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, context: context)
    }
#endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
#if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
#else
        webView.scrollView.contentInsetAdjustmentBehavior = .never
#endif
        return webView
    }

    private func update(_ webView: WKWebView, context: Context) {
        context.coordinator.updateParent(self)
        context.coordinator.applyAdBlockingIfNeeded(adBlockingMode, webView: webView)
        guard context.coordinator.isAdBlockingReady else { return }
        context.coordinator.processPendingWork(webView: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BrowserWebView
        var modelLoadTracker = BrowserModelLoadRevisionTracker()
        var lastHandledCommandID: UUID?
        var lastAppliedAdBlockingMode: BrowserAdBlockingMode?
        var isAdBlockingReady = false
        var lastHandledAutomationID: UUID?
        var pendingAutomationIDs = Set<UUID>()
        var pendingTimeouts: [UUID: DispatchWorkItem] = [:]
        var ownedApprovedAutomationRequestIDs = Set<UUID>()
        var navigationGenerationAwaitingModelUpdate: UInt64?
        let automationDispatchOwnerID = UUID()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        init(_ parent: BrowserWebView) {
            self.parent = parent
        }

        func updateParent(_ updatedParent: BrowserWebView) {
            parent = updatedParent
            if let generationAtNavigationStart = navigationGenerationAwaitingModelUpdate,
               updatedParent.navigationGeneration != generationAtNavigationStart {
                navigationGenerationAwaitingModelUpdate = nil
            }
        }

        func applyAdBlockingIfNeeded(_ mode: BrowserAdBlockingMode, webView: WKWebView) {
            guard lastAppliedAdBlockingMode != mode else { return }
            lastAppliedAdBlockingMode = mode
            isAdBlockingReady = false
            BrowserAdBlocker.apply(
                to: webView.configuration.userContentController,
                mode: mode,
                isCurrent: { [weak self] in
                    self?.lastAppliedAdBlockingMode == mode
                }
            ) { [weak self, weak webView] in
                guard let self, let webView else { return }
                guard self.lastAppliedAdBlockingMode == mode else { return }
                self.isAdBlockingReady = true
                self.processPendingWork(webView: webView)
            }
        }

        func processPendingWork(webView: WKWebView) {
            applyCommandIfNeeded(parent.command, webView: webView)
            applyAutomationIfNeeded(parent.automationRequest, webView: webView)
            loadTabIfNeeded(webView)
        }

        private func applyCommandIfNeeded(_ command: BrowserWebCommandRequest?, webView: WKWebView) {
            guard let command else { return }
            guard command.tabID == parent.tab.id else { return }
            guard lastHandledCommandID != command.id else { return }
            lastHandledCommandID = command.id

            switch command.command {
            case .back:
                if webView.canGoBack {
                    webView.goBack()
                }
            case .forward:
                if webView.canGoForward {
                    webView.goForward()
                }
            case .reload:
                webView.reload()
            case .stop:
                webView.stopLoading()
            }
        }

        private func loadTabIfNeeded(_ webView: WKWebView) {
            guard let url = parent.tab.loadableURL else { return }
            guard modelLoadTracker.shouldHandle(parent.tab.modelLoadRevision) else { return }
            webView.load(URLRequest(url: url))
        }

        func applyAutomationIfNeeded(_ request: BrowserAutomationRequest?, webView: WKWebView) {
            guard let request else { return }
            guard request.tabID == parent.tab.id else { return }
            guard lastHandledAutomationID != request.id else { return }
            lastHandledAutomationID = request.id

            if request.approvalGrant != nil {
                guard parent.onApprovedAutomationDispatch(
                    request.id,
                    automationDispatchOwnerID
                ) else {
                    // Another coordinator already owns this one-time grant and
                    // its callback (or the view-model timeout) owns the only
                    // terminal outcome that may be accepted.
                    return
                }
                ownedApprovedAutomationRequestIDs.insert(request.id)
            }

            if let grant = request.approvalGrant,
               (navigationGenerationAwaitingModelUpdate != nil
                || webView.isLoading
                || !BrowserAutomationGrantPolicy.matches(
                    grant,
                    request: request,
                    currentURLString: webView.url?.absoluteString,
                    currentNavigationGeneration: parent.navigationGeneration
                )) {
                publishAutomation(
                    BrowserAutomationResult(
                        requestID: request.id,
                        tabID: request.tabID,
                        status: .failed,
                        message: "The approved command no longer matches the exact page that is loaded."
                    )
                )
                return
            }

            if case .action(let action) = request.command {
                if action.kind == .stop {
                    webView.stopLoading()
                    publishAutomation(
                        BrowserAutomationResult(
                            requestID: request.id,
                            tabID: request.tabID,
                            status: .success,
                            message: "Stopped page loading.",
                            actionResult: BrowserActionResult(
                                actionKind: .stop,
                                success: true,
                                message: "Stopped page loading.",
                                urlString: webView.url?.absoluteString,
                                title: webView.title,
                                affectedElement: nil
                            )
                        )
                    )
                    return
                }

                if request.approvalGrant == nil,
                   let approval = BrowserAutomationApprovalPolicy.evaluate(
                    action: action,
                    currentURLString: webView.url?.absoluteString
                ) {
                    publishAutomation(
                        BrowserAutomationResult(
                            requestID: request.id,
                            tabID: request.tabID,
                            status: .needsApproval,
                            message: approval.summary,
                            approval: approval
                        )
                    )
                    return
                }
            }

            let script: String
            do {
                script = try automationScript(for: request)
            } catch {
                publishAutomation(
                    BrowserAutomationResult(
                        requestID: request.id,
                        tabID: request.tabID,
                        status: .failed,
                        message: error.localizedDescription
                    )
                )
                return
            }

            pendingAutomationIDs.insert(request.id)
            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.pendingAutomationIDs.remove(request.id) != nil else { return }
                self.pendingTimeouts.removeValue(forKey: request.id)
                self.publishAutomation(
                    BrowserAutomationResult(
                        requestID: request.id,
                        tabID: request.tabID,
                        status: .timedOut,
                        message: "Automation request timed out."
                    )
                )
            }
            pendingTimeouts[request.id] = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + request.timeoutSeconds, execute: timeout)

            webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                guard self.pendingAutomationIDs.remove(request.id) != nil else { return }
                self.pendingTimeouts.removeValue(forKey: request.id)?.cancel()

                if let error {
                    self.publishAutomation(
                        BrowserAutomationResult(
                            requestID: request.id,
                            tabID: request.tabID,
                            status: .failed,
                            message: error.localizedDescription
                        )
                    )
                    return
                }

                do {
                    let result = try self.decodeAutomationResult(
                        request: request,
                        value: value,
                        webView: webView
                    )
                    self.publishAutomation(result)
                } catch {
                    self.publishAutomation(
                        BrowserAutomationResult(
                            requestID: request.id,
                            tabID: request.tabID,
                            status: .failed,
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Record the document transition synchronously. The view model's
            // generation increments through an async delegate publication, so
            // URL/isLoading alone cannot safely authorize a same-URL reload in
            // the interval before SwiftUI propagates the new generation back.
            navigationGenerationAwaitingModelUpdate = parent.navigationGeneration
            publish(webView: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            publish(webView: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationGenerationAwaitingModelUpdate = nil
            publish(webView: webView, isLoading: false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            navigationGenerationAwaitingModelUpdate = nil
            publish(webView: webView, isLoading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            navigationGenerationAwaitingModelUpdate = nil
            publish(webView: webView, isLoading: false)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            navigationGenerationAwaitingModelUpdate = nil
            publish(webView: webView, isLoading: false)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased()
            if scheme == "http" || scheme == "https" {
                // WebKit owns this request, including its method and body.
                // Mirroring its destination into BrowserTab does not advance the
                // model load revision, so reconciliation cannot replay it.
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func publish(webView: WKWebView, isLoading: Bool) {
            let update = BrowserNavigationUpdate(
                tabID: parent.tab.id,
                urlString: webView.url?.absoluteString,
                title: webView.title,
                isLoading: isLoading,
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward
            )
            DispatchQueue.main.async {
                self.parent.onNavigationUpdate(update)
            }
        }

        private func publishAutomation(_ result: BrowserAutomationResult) {
            var ownedResult = result
            if ownedApprovedAutomationRequestIDs.remove(result.requestID) != nil {
                ownedResult.approvedAutomationDispatchOwnerID = automationDispatchOwnerID
            }
            let publishedResult = ownedResult
            DispatchQueue.main.async {
                self.parent.onAutomationResult(publishedResult)
            }
        }

        private func decodeAutomationResult(
            request: BrowserAutomationRequest,
            value: Any?,
            webView: WKWebView
        ) throws -> BrowserAutomationResult {
            switch request.command {
            case .domQuery:
                let domQuery = try decode(DOMQueryResult.self, from: value)
                return BrowserAutomationResult(
                    requestID: request.id,
                    tabID: request.tabID,
                    status: .success,
                    message: "DOM query returned \(domQuery.elements.count) element\(domQuery.elements.count == 1 ? "" : "s").",
                    domQuery: domQuery
                )
            case .pageSnapshot:
                let snapshot = try decode(PageSnapshot.self, from: value)
                return BrowserAutomationResult(
                    requestID: request.id,
                    tabID: request.tabID,
                    status: .success,
                    message: "Page snapshot captured \(snapshot.visibleText.count) text characters.",
                    pageSnapshot: snapshot
                )
            case .textSelection:
                let selection = try decode(BrowserTextSelection.self, from: value)
                return BrowserAutomationResult(
                    requestID: request.id,
                    tabID: request.tabID,
                    status: selection.text.isEmpty ? .failed : .success,
                    message: selection.text.isEmpty
                        ? "No eligible page text selection was available."
                        : "Captured \(selection.text.count) selected text characters.",
                    textSelection: selection
                )
            case .action:
                let actionResult = try decode(BrowserActionResult.self, from: value)
                return BrowserAutomationResult(
                    requestID: request.id,
                    tabID: request.tabID,
                    status: actionResult.success ? .success : .failed,
                    message: actionResult.message,
                    actionResult: actionResult
                )
            }
        }

        private func decode<T: Decodable>(_ type: T.Type, from value: Any?) throws -> T {
            if let string = value as? String, let data = string.data(using: .utf8) {
                return try decoder.decode(type, from: data)
            }
            if let value {
                let data = try JSONSerialization.data(withJSONObject: value)
                return try decoder.decode(type, from: data)
            }
            throw CocoaError(.coderReadCorrupt)
        }

        private func automationScript(for request: BrowserAutomationRequest) throws -> String {
            switch request.command {
            case .domQuery(let domQuery):
                return try domQueryScript(request: domQuery)
            case .pageSnapshot(let snapshot):
                return try pageSnapshotScript(request: snapshot)
            case .textSelection(let request):
                return try textSelectionScript(request: request)
            case .action(let action):
                return try actionScript(action: action)
            }
        }

        private func jsonLiteral<T: Encodable>(_ value: T) throws -> String {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        private func domQueryScript(request: DOMQueryRequest) throws -> String {
            let requestJSON = try jsonLiteral(request)
            return """
            (() => {
              const request = \(requestJSON);
              const redactionTerms = ['password', 'passcode', 'secret', 'token', 'seed', 'private', 'credential'];
              const compact = (value, limit = 180) => {
                if (value === null || value === undefined) return null;
                const text = String(value).replace(/\\s+/g, ' ').trim();
                return text.length > limit ? text.slice(0, limit) : text;
              };
              const isHidden = (el) => {
                const style = window.getComputedStyle(el);
                const rect = el.getBoundingClientRect();
                return el.hidden || style.display === 'none' || style.visibility === 'hidden' || rect.width === 0 || rect.height === 0;
              };
              const safeValue = (el) => {
                const probe = [el.type, el.name, el.id, el.placeholder, el.getAttribute('aria-label')]
                  .filter(Boolean).join(' ').toLowerCase();
                if (redactionTerms.some(term => probe.includes(term))) return '[redacted]';
                if (!('value' in el)) return null;
                return compact(el.value, 120);
              };
              const record = (el, index) => ({
                index,
                tagName: el.tagName.toLowerCase(),
                role: compact(el.getAttribute('role')),
                ariaLabel: compact(el.getAttribute('aria-label')),
                text: compact(el.innerText || el.textContent),
                value: safeValue(el),
                href: compact(el.href || el.src || el.action),
                inputType: compact(el.type),
                name: compact(el.name || el.id),
                placeholder: compact(el.placeholder),
                disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true'),
                hidden: isHidden(el)
              });
              let nodes;
              try {
                nodes = Array.from(document.querySelectorAll(request.selector));
              } catch (error) {
                return JSON.stringify({ selector: request.selector, elements: [], totalMatched: 0, truncated: false });
              }
              const filtered = request.includeHidden ? nodes : nodes.filter(el => !isHidden(el));
              const elements = filtered.slice(0, request.limit).map(record);
              return JSON.stringify({
                selector: request.selector,
                elements,
                totalMatched: filtered.length,
                truncated: filtered.length > elements.length
              });
            })();
            """
        }

        private func pageSnapshotScript(request: PageSnapshotRequest) throws -> String {
            let requestJSON = try jsonLiteral(request)
            return """
            (() => {
              const request = \(requestJSON);
              const redactionTerms = ['password', 'passcode', 'secret', 'token', 'seed', 'private', 'credential'];
              let redactionCount = 0;
              const compact = (value, limit = 220) => {
                if (value === null || value === undefined) return null;
                const text = String(value).replace(/\\s+/g, ' ').trim();
                return text.length > limit ? text.slice(0, limit) : text;
              };
              const isHidden = (el) => {
                const style = window.getComputedStyle(el);
                const rect = el.getBoundingClientRect();
                return el.hidden || style.display === 'none' || style.visibility === 'hidden' || rect.width === 0 || rect.height === 0;
              };
              const safeValue = (el) => {
                const probe = [el.type, el.name, el.id, el.placeholder, el.getAttribute('aria-label')]
                  .filter(Boolean).join(' ').toLowerCase();
                if (redactionTerms.some(term => probe.includes(term))) {
                  redactionCount += 1;
                  return '[redacted]';
                }
                if (!('value' in el)) return null;
                return compact(el.value, 120);
              };
              const record = (el, index) => ({
                index,
                tagName: el.tagName.toLowerCase(),
                role: compact(el.getAttribute('role')),
                ariaLabel: compact(el.getAttribute('aria-label')),
                text: compact(el.innerText || el.textContent),
                value: safeValue(el),
                href: compact(el.href || el.src || el.action),
                inputType: compact(el.type),
                name: compact(el.name || el.id),
                placeholder: compact(el.placeholder),
                disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true'),
                hidden: isHidden(el)
              });
              const visibleText = compact(document.body ? document.body.innerText : '', request.maxTextCharacters) || '';
              const headings = Array.from(document.querySelectorAll('h1,h2,h3'))
                .filter(el => !isHidden(el))
                .map(el => compact(el.innerText || el.textContent, 160))
                .filter(Boolean)
                .slice(0, request.maxElements);
              const links = Array.from(document.querySelectorAll('a[href]')).filter(el => !isHidden(el)).slice(0, request.maxElements).map(record);
              const buttons = Array.from(document.querySelectorAll('button,input[type=button],input[type=submit],[role=button]')).filter(el => !isHidden(el)).slice(0, request.maxElements).map(record);
              const formControls = Array.from(document.querySelectorAll('input,textarea,select')).filter(el => !isHidden(el)).slice(0, request.maxElements).map(record);
              const metadata = {};
              if (request.includeMetadata) {
                Array.from(document.querySelectorAll('meta[name],meta[property]')).slice(0, 30).forEach(meta => {
                  const key = compact(meta.getAttribute('name') || meta.getAttribute('property'), 120);
                  const value = meta.getAttribute('content');
                  if (key && value) metadata[key] = compact(value, 240);
                });
              }
              return JSON.stringify({
                urlString: compact(String(location.href), 2048) || '',
                title: compact(document.title || '', 200) || '',
                visibleText,
                headings,
                links,
                buttons,
                formControls,
                metadata,
                truncated: Boolean(document.body && document.body.innerText && document.body.innerText.length > request.maxTextCharacters),
                redactionCount
              });
            })();
            """
        }

        private func textSelectionScript(request: BrowserTextSelectionRequest) throws -> String {
            let requestJSON = try jsonLiteral(request)
            return """
            (() => {
              const request = \(requestJSON);
              const selection = window.getSelection();
              const elementForNode = (node) => node
                ? (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement)
                : null;
              const anchor = elementForNode(selection && selection.anchorNode);
              const focus = elementForNode(selection && selection.focusNode);
              const sensitiveOwner = (element) => element && element.closest
                ? element.closest('input,textarea,select,form,[contenteditable]')
                : null;
              const sensitiveContainer = sensitiveOwner(anchor) || sensitiveOwner(focus);
              if (sensitiveContainer) {
                return JSON.stringify({
                  text: '',
                  urlString: String(location.href),
                  elementTagName: String(sensitiveContainer.tagName || '').toLowerCase(),
                  truncated: false
                });
              }
              let rawText = selection ? String(selection.toString()) : '';
              if (selection && selection.rangeCount > 0) {
                try {
                  const fragment = selection.getRangeAt(0).cloneContents();
                  if (fragment.querySelectorAll) {
                    fragment.querySelectorAll('input,textarea,select,form,[contenteditable]').forEach(node => node.remove());
                    rawText = String(fragment.textContent || '');
                  }
                } catch (_) {
                  rawText = '';
                }
              }
              const normalized = rawText.replace(/\\s+/g, ' ').trim();
              const text = normalized.slice(0, request.maximumCharacters);
              return JSON.stringify({
                text,
                urlString: String(location.href),
                elementTagName: anchor && anchor.tagName ? String(anchor.tagName).toLowerCase() : null,
                truncated: normalized.length > text.length
              });
            })();
            """
        }

        private func actionScript(action: BrowserDOMAction) throws -> String {
            let actionJSON = try jsonLiteral(action)
            return """
            (() => {
              const action = \(actionJSON);
              const compact = (value, limit = 180) => {
                if (value === null || value === undefined) return null;
                const text = String(value).replace(/\\s+/g, ' ').trim();
                return text.length > limit ? text.slice(0, limit) : text;
              };
              const isHidden = (el) => {
                const style = window.getComputedStyle(el);
                const rect = el.getBoundingClientRect();
                return el.hidden || style.display === 'none' || style.visibility === 'hidden' || rect.width === 0 || rect.height === 0;
              };
              const record = (el, index) => el ? ({
                index,
                tagName: el.tagName.toLowerCase(),
                role: compact(el.getAttribute('role')),
                ariaLabel: compact(el.getAttribute('aria-label')),
                text: compact(el.innerText || el.textContent),
                value: 'value' in el ? compact(el.value, 120) : null,
                href: compact(el.href || el.src || el.action),
                inputType: compact(el.type),
                name: compact(el.name || el.id),
                placeholder: compact(el.placeholder),
                disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true'),
                hidden: isHidden(el)
              }) : null;
              const nodes = action.selector ? Array.from(document.querySelectorAll(action.selector)) : [];
              const index = action.elementIndex || 0;
              const el = nodes[index] || null;
              const result = (success, message, affectedElement = el) => JSON.stringify({
                actionKind: action.kind,
                success,
                message,
                urlString: String(location.href),
                title: document.title || '',
                affectedElement: record(affectedElement, index)
              });
              try {
                switch (action.kind) {
                case 'scroll':
                  window.scrollBy(action.x || 0, action.y || 0);
                  return result(true, 'Scrolled page.', null);
                case 'navigate':
                  if (!action.urlString) return result(false, 'Navigate action missing URL.', null);
                  window.location.href = action.urlString;
                  return result(true, 'Navigation requested.', null);
                case 'waitForSelector':
                  return result(Boolean(el), el ? 'Selector is present.' : 'Selector was not found.', el);
                case 'focus':
                  if (!el) return result(false, 'Focus target was not found.', null);
                  el.focus();
                  return result(true, 'Focused element.', el);
                case 'typeText':
                  if (!el) return result(false, 'Type target was not found.', null);
                  el.focus();
                  if ('value' in el) {
                    el.value = action.clearExistingText ? (action.text || '') : String(el.value || '') + (action.text || '');
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                    return result(true, 'Typed text into element.', el);
                  }
                  if (el.isContentEditable) {
                    el.textContent = action.clearExistingText
                      ? (action.text || '')
                      : String(el.textContent || '') + (action.text || '');
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    return result(true, 'Typed text into editable content.', el);
                  }
                  return result(false, 'Type target is not editable.', el);
                case 'submit':
                  if (!el) return result(false, 'Submit target was not found.', null);
                  const form = el.tagName && el.tagName.toLowerCase() === 'form' ? el : el.closest('form');
                  if (!form) return result(false, 'No form found for submit action.', el);
                  if (form.requestSubmit) form.requestSubmit(); else form.submit();
                  return result(true, 'Submitted form.', form);
                case 'click':
                  if (!el) return result(false, 'Click target was not found.', null);
                  el.click();
                  return result(true, 'Clicked element.', el);
                default:
                  return result(false, 'Unsupported action.', el);
                }
              } catch (error) {
                return result(false, String(error && error.message ? error.message : error), el);
              }
            })();
            """
        }
    }
}
