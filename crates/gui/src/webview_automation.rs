use std::sync::{Arc, Mutex};
use std::time::Duration;

use agent_core::{DomAction, DomExecutionResult};
use serde_json::{json, Value};
use tauri::{AppHandle, Manager, Wry};
use tokio::sync::oneshot;
use tokio::time::timeout;

use crate::app_state::AppState;

const AUTOMATION_TIMEOUT: Duration = Duration::from_secs(8);
const DEFAULT_QUERY_LIMIT: usize = 20;
const DEFAULT_SNAPSHOT_ITEM_LIMIT: usize = 20;
const DEFAULT_MAIN_TEXT_LIMIT: usize = 4000;

pub fn active_tab_id(app_handle: &AppHandle<Wry>) -> Result<Option<String>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    state
        .active_content_tab
        .lock()
        .map_err(|_| "active tab mutex poisoned".to_string())
        .map(|active| active.clone())
}

pub fn active_tab_webview(
    app_handle: &AppHandle<Wry>,
) -> Result<tauri::webview::Webview<Wry>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    let active_tab_id = state
        .active_content_tab
        .lock()
        .map_err(|_| "active tab mutex poisoned".to_string())?
        .clone()
        .ok_or_else(|| "active tab webview is not available".to_string())?;

    let label = state
        .content_tab_webviews
        .lock()
        .map_err(|_| "content webview map mutex poisoned".to_string())?
        .get(&active_tab_id)
        .cloned()
        .ok_or_else(|| "active tab webview is not registered".to_string())?;

    app_handle
        .get_webview(&label)
        .ok_or_else(|| "active tab webview is not available".to_string())
}

pub async fn query_active_dom(
    app_handle: &AppHandle<Wry>,
    selector: &str,
    limit: Option<usize>,
) -> Result<Value, String> {
    let limit = limit.unwrap_or(DEFAULT_QUERY_LIMIT).clamp(1, 100);
    let script = format!(
        r#"(() => {{
            const selector = {selector};
            const limit = {limit};
            const normalizeText = (value) => String(value || '')
              .replace(/\s+/g, ' ')
              .trim()
              .slice(0, 280);
            const asRect = (node) => {{
              if (!node || typeof node.getBoundingClientRect !== 'function') {{
                return null;
              }}
              const rect = node.getBoundingClientRect();
              return {{
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                width: Math.round(rect.width),
                height: Math.round(rect.height),
              }};
            }};
            const nodes = Array.from(document.querySelectorAll(selector));
            return {{
              selector,
              totalMatches: nodes.length,
              returned: Math.min(nodes.length, limit),
              url: window.location.href,
              title: document.title || window.location.href,
              matches: nodes.slice(0, limit).map((node, index) => {{
                const className = typeof node.className === 'string' ? node.className : '';
                return {{
                  index,
                  tag: node.tagName ? node.tagName.toLowerCase() : null,
                  id: node.id || null,
                  classes: className.split(/\s+/).filter(Boolean).slice(0, 8),
                  text: normalizeText(node.innerText || node.textContent || ''),
                  href: node.href || node.getAttribute?.('href') || null,
                  ariaLabel: node.getAttribute?.('aria-label') || null,
                  placeholder: node.getAttribute?.('placeholder') || null,
                  value: 'value' in node ? normalizeText(node.value) : null,
                  rect: asRect(node),
                }};
              }}),
            }};
        }})()"#,
        selector = json_string(selector),
        limit = limit
    );

    let result = evaluate_active_json(app_handle, &script).await?;
    sync_active_tab_metadata(app_handle, &result)?;
    Ok(result)
}

pub async fn snapshot_active_page(app_handle: &AppHandle<Wry>) -> Result<Value, String> {
    let script = format!(
        r#"(() => {{
            const itemLimit = {item_limit};
            const textLimit = {text_limit};
            const normalizeText = (value) => String(value || '')
              .replace(/\s+/g, ' ')
              .trim();
            const visible = (element) => {{
              if (!element || typeof element.getBoundingClientRect !== 'function') {{
                return false;
              }}
              const rect = element.getBoundingClientRect();
              const style = window.getComputedStyle(element);
              return rect.width > 0
                && rect.height > 0
                && style.visibility !== 'hidden'
                && style.display !== 'none';
            }};
            const summarizeText = (value, max) => normalizeText(value).slice(0, max);
            const linkPayload = (node) => {{
              const text = summarizeText(node.innerText || node.textContent || '', 220);
              return {{
                text,
                href: node.href || node.getAttribute?.('href') || null,
                ariaLabel: node.getAttribute?.('aria-label') || null,
              }};
            }};
            const buttonPayload = (node) => {{
              const text = summarizeText(node.innerText || node.textContent || node.value || '', 160);
              return {{
                text,
                tag: node.tagName ? node.tagName.toLowerCase() : null,
                type: node.getAttribute?.('type') || null,
                ariaLabel: node.getAttribute?.('aria-label') || null,
                disabled: !!node.disabled,
              }};
            }};
            const fieldPayload = (node) => {{
              const labelId = node.getAttribute?.('id');
              let labelText = null;
              if (labelId) {{
                const label = document.querySelector(`label[for="${{labelId}}"]`);
                if (label) {{
                  labelText = summarizeText(label.innerText || label.textContent || '', 120);
                }}
              }}
              if (!labelText) {{
                const parentLabel = node.closest?.('label');
                if (parentLabel) {{
                  labelText = summarizeText(parentLabel.innerText || parentLabel.textContent || '', 120);
                }}
              }}
              return {{
                name: node.getAttribute?.('name') || null,
                type: node.getAttribute?.('type') || node.tagName?.toLowerCase() || null,
                placeholder: node.getAttribute?.('placeholder') || null,
                ariaLabel: node.getAttribute?.('aria-label') || null,
                label: labelText,
                required: !!node.required,
                disabled: !!node.disabled,
              }};
            }};

            const mainNode = document.querySelector('main, article, [role="main"]') || document.body;
            const headings = Array.from(document.querySelectorAll('h1, h2, h3'))
              .map((node) => summarizeText(node.innerText || node.textContent || '', 160))
              .filter(Boolean)
              .slice(0, 12);
            const keyLinks = Array.from(document.querySelectorAll('a[href]'))
              .filter(visible)
              .map(linkPayload)
              .filter((entry) => entry.text || entry.href)
              .slice(0, itemLimit);
            const keyButtons = Array.from(document.querySelectorAll('button, [role="button"], input[type="submit"], input[type="button"]'))
              .filter(visible)
              .map(buttonPayload)
              .filter((entry) => entry.text || entry.ariaLabel)
              .slice(0, itemLimit);
            const forms = Array.from(document.forms)
              .slice(0, 8)
              .map((form, index) => {{
                const fields = Array.from(form.elements || [])
                  .filter((node) => node instanceof HTMLElement)
                  .map(fieldPayload)
                  .slice(0, itemLimit);
                return {{
                  index,
                  action: form.action || null,
                  method: (form.method || 'get').toLowerCase(),
                  fields,
                }};
              }});

            return {{
              url: window.location.href,
              title: document.title || window.location.href,
              headings,
              mainText: summarizeText(mainNode?.innerText || mainNode?.textContent || '', textLimit),
              keyLinks,
              keyButtons,
              forms,
            }};
        }})()"#,
        item_limit = DEFAULT_SNAPSHOT_ITEM_LIMIT,
        text_limit = DEFAULT_MAIN_TEXT_LIMIT
    );

    let result = evaluate_active_json(app_handle, &script).await?;
    sync_active_tab_metadata(app_handle, &result)?;
    Ok(result)
}

pub async fn execute_active_dom_action(
    app_handle: &AppHandle<Wry>,
    action: &DomAction,
) -> Result<DomExecutionResult, String> {
    match action {
        DomAction::Navigate { url } => {
            let webview = active_tab_webview(app_handle)?;
            let target = url::Url::parse(url.trim())
                .or_else(|_| url::Url::parse(&format!("https://{}", url.trim())))
                .map_err(|err| format!("invalid url: {err}"))?;
            webview
                .navigate(target)
                .map_err(|err| format!("navigation failed: {err}"))?;
            Ok(DomExecutionResult::with_details(
                format!("navigated to {}", url.trim()),
                json!({ "url": url.trim() }),
            ))
        }
        DomAction::Click { selector } => {
            let script = format!(
                r#"(() => {{
                    const selector = {selector};
                    const normalizeText = (value) => String(value || '')
                      .replace(/\s+/g, ' ')
                      .trim()
                      .slice(0, 200);
                    const element = document.querySelector(selector);
                    if (!element) {{
                      return {{ ok: false, error: 'selector not found', selector }};
                    }}
                    element.scrollIntoView({{ block: 'center', inline: 'center', behavior: 'instant' }});
                    if (typeof element.focus === 'function') {{
                      element.focus();
                    }}
                    if (typeof element.click === 'function') {{
                      element.click();
                    }} else {{
                      element.dispatchEvent(new MouseEvent('click', {{ bubbles: true, cancelable: true, composed: true }}));
                    }}
                    return {{
                      ok: true,
                      selector,
                      tag: element.tagName ? element.tagName.toLowerCase() : null,
                      text: normalizeText(element.innerText || element.textContent || element.value || ''),
                    }};
                }})()"#,
                selector = json_string(selector)
            );
            action_result(
                "clicked",
                selector,
                evaluate_active_json(app_handle, &script).await?,
            )
        }
        DomAction::Type { selector, text } => {
            let script = format!(
                r#"(() => {{
                    const selector = {selector};
                    const text = {text};
                    const element = document.querySelector(selector);
                    if (!element) {{
                      return {{ ok: false, error: 'selector not found', selector }};
                    }}
                    element.scrollIntoView({{ block: 'center', inline: 'center', behavior: 'instant' }});
                    if (typeof element.focus === 'function') {{
                      element.focus();
                    }}
                    if ('value' in element) {{
                      element.value = text;
                    }} else if (element.isContentEditable) {{
                      element.textContent = text;
                    }} else {{
                      return {{ ok: false, error: 'element is not typable', selector }};
                    }}
                    element.dispatchEvent(new Event('input', {{ bubbles: true, cancelable: true }}));
                    element.dispatchEvent(new Event('change', {{ bubbles: true, cancelable: true }}));
                    return {{
                      ok: true,
                      selector,
                      characters: text.length,
                      tag: element.tagName ? element.tagName.toLowerCase() : null,
                    }};
                }})()"#,
                selector = json_string(selector),
                text = json_string(text)
            );
            action_result(
                "typed into",
                selector,
                evaluate_active_json(app_handle, &script).await?,
            )
        }
        DomAction::Scroll { dx, dy } => {
            let script = format!(
                r#"(() => {{
                    window.scrollBy({dx}, {dy});
                    return {{
                      ok: true,
                      dx: {dx},
                      dy: {dy},
                      scrollX: Math.round(window.scrollX),
                      scrollY: Math.round(window.scrollY),
                    }};
                }})()"#,
                dx = dx,
                dy = dy
            );
            let result = evaluate_active_json(app_handle, &script).await?;
            ensure_action_ok(&result)?;
            Ok(DomExecutionResult::with_details(
                format!("scrolled by dx={}, dy={}", dx, dy),
                result,
            ))
        }
    }
}

pub async fn evaluate_active_json(
    app_handle: &AppHandle<Wry>,
    script: &str,
) -> Result<Value, String> {
    let webview = active_tab_webview(app_handle)?;
    evaluate_json(&webview, script).await
}

pub async fn evaluate_json(
    webview: &tauri::webview::Webview<Wry>,
    script: &str,
) -> Result<Value, String> {
    #[cfg(target_os = "macos")]
    {
        use block2::RcBlock;
        use objc2::runtime::AnyObject;
        use objc2::AnyThread;
        use objc2_foundation::{
            NSError, NSJSONSerialization, NSJSONWritingOptions, NSString, NSUTF8StringEncoding,
        };
        use objc2_web_kit::WKWebView;

        let (tx, rx) = oneshot::channel::<Result<String, String>>();
        let sender = Arc::new(Mutex::new(Some(tx)));
        let script_owned = script.to_string();
        let sender_for_eval = sender.clone();

        webview
            .with_webview(move |platform| unsafe {
                let view: &WKWebView = &*platform.inner().cast();
                let sender_for_callback = sender_for_eval.clone();
                let handler = RcBlock::new(move |value: *mut AnyObject, err: *mut NSError| {
                    let result = if !err.is_null() {
                        Err((&*err).localizedDescription().to_string())
                    } else if value.is_null() {
                        Ok("null".to_string())
                    } else {
                        let data = NSJSONSerialization::dataWithJSONObject_options_error(
                            &*value,
                            NSJSONWritingOptions::FragmentsAllowed,
                        )
                        .map_err(|err| err.localizedDescription().to_string());

                        data.and_then(|json_data| {
                            NSString::initWithData_encoding(
                                NSString::alloc(),
                                &json_data,
                                NSUTF8StringEncoding,
                            )
                            .map(|json| json.to_string())
                            .ok_or_else(|| {
                                "JavaScript evaluation returned non-UTF8 data".to_string()
                            })
                        })
                    };

                    if let Ok(mut slot) = sender_for_callback.lock() {
                        if let Some(sender) = slot.take() {
                            let _ = sender.send(result);
                        }
                    }
                });

                view.evaluateJavaScript_completionHandler(
                    &NSString::from_str(&script_owned),
                    Some(&handler),
                );
            })
            .map_err(|err| format!("failed to evaluate JavaScript: {err}"))?;

        match timeout(AUTOMATION_TIMEOUT, rx).await {
            Ok(Ok(Ok(payload))) => serde_json::from_str(&payload)
                .map_err(|err| format!("failed to decode JavaScript result: {err}")),
            Ok(Ok(Err(err))) => Err(err),
            Ok(Err(_)) => Err("JavaScript evaluation channel closed".to_string()),
            Err(_) => Err("JavaScript evaluation timed out".to_string()),
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = (webview, script);
        Err("webview automation bridge is only implemented for macOS builds".to_string())
    }
}

fn action_result(verb: &str, selector: &str, result: Value) -> Result<DomExecutionResult, String> {
    ensure_action_ok(&result)?;
    Ok(DomExecutionResult::with_details(
        format!("{verb} {selector}"),
        result,
    ))
}

fn ensure_action_ok(result: &Value) -> Result<(), String> {
    match result.get("ok").and_then(Value::as_bool) {
        Some(true) => Ok(()),
        Some(false) => Err(result
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("DOM action failed")
            .to_string()),
        None => Ok(()),
    }
}

fn sync_active_tab_metadata(app_handle: &AppHandle<Wry>, payload: &Value) -> Result<(), String> {
    let title = payload
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let url = payload
        .get("url")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();

    if title.is_empty() && url.is_empty() {
        return Ok(());
    }

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let active_tab_id = state
        .active_content_tab
        .lock()
        .map_err(|_| "active tab mutex poisoned".to_string())?
        .clone();

    if let Some(tab_id) = active_tab_id {
        state
            .browser_engine
            .update_tab(
                &tab_id,
                (!title.is_empty()).then_some(title),
                (!url.is_empty()).then_some(url.clone()),
                None,
            )
            .map_err(|err| err.to_string())?;
        if !url.is_empty() {
            state
                .browser_engine
                .add_to_history(url.clone(), payload_title(payload))
                .map_err(|err| err.to_string())?;
        }
    }

    if !url.is_empty() {
        if let Ok(mut current_url) = state.current_url.lock() {
            *current_url = url;
        }
    }

    Ok(())
}

fn payload_title(payload: &Value) -> String {
    payload
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or_else(|| {
            payload
                .get("url")
                .and_then(Value::as_str)
                .unwrap_or("Untitled")
        })
        .to_string()
}

fn json_string(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string())
}
