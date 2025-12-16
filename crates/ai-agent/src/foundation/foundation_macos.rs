use std::ffi::{c_char, c_void, CString};
use std::ptr;

use anyhow::{anyhow, Result};
use core_foundation::base::TCFType;
use core_foundation::string::CFString;
use tokio::task;

use crate::foundation::FoundationModelOptions;
use crate::language_model::{LanguageModelClient, LanguageModelResponse};

extern "C" {
    fn foundation_model_generate(
        prompt: *const c_char,
        system_prompt: *const c_char,
        temperature: f64,
        max_tokens: i32,
        out_text: *mut *mut c_void,
        out_error_message: *mut *mut c_void,
    ) -> i32;
}

#[derive(Debug, Clone)]
pub struct MacFoundationClient;

impl MacFoundationClient {
    pub fn new() -> Result<Self> {
        Ok(Self {})
    }

    fn invoke(
        &self,
        prompt: &str,
        options: &FoundationModelOptions,
    ) -> Result<LanguageModelResponse> {
        let prompt_c =
            CString::new(prompt).map_err(|_| anyhow!("Prompt contains interior null byte"))?;
        let sys_prompt = if let Some(system) = &options.system_prompt {
            Some(
                CString::new(system.as_str())
                    .map_err(|_| anyhow!("System prompt contains interior null byte"))?,
            )
        } else {
            None
        };

        let mut out_text: *mut c_void = ptr::null_mut();
        let mut out_error: *mut c_void = ptr::null_mut();

        let status = unsafe {
            foundation_model_generate(
                prompt_c.as_ptr(),
                sys_prompt
                    .as_ref()
                    .map(|s| s.as_ptr())
                    .unwrap_or(ptr::null()),
                options.temperature as f64,
                options.max_tokens.unwrap_or(512) as i32,
                &mut out_text,
                &mut out_error,
            )
        };

        if status != 0 {
            let err_msg = if !out_error.is_null() {
                let cf_msg = unsafe { CFString::wrap_under_create_rule(out_error as _) };
                Some(cf_msg.to_string())
            } else {
                None
            };
            return Err(anyhow!(err_msg.unwrap_or_else(|| format!(
                "Foundation model call failed with status {}",
                status
            ))));
        }

        if out_text.is_null() {
            return Err(anyhow!("Foundation model returned no content"));
        }

        let cf_text = unsafe { CFString::wrap_under_create_rule(out_text as _) };
        let text = cf_text.to_string();
        Ok(LanguageModelResponse::new(text))
    }
}

#[async_trait::async_trait]
impl LanguageModelClient for MacFoundationClient {
    async fn complete(
        &self,
        prompt: &str,
        options: &FoundationModelOptions,
    ) -> Result<LanguageModelResponse> {
        let prompt_owned = prompt.to_owned();
        let options_owned = options.clone();
        tracing::debug!(target: "ai_agent::foundation", prompt_length = prompt.len(), temperature = options.temperature, max_tokens = ?options.max_tokens);
        task::spawn_blocking(move || {
            let client = MacFoundationClient {};
            client.invoke(&prompt_owned, &options_owned)
        })
        .await
        .map_err(|err| anyhow!("Foundation model invocation panicked: {err}"))?
    }
}
