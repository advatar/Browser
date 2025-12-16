use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use p256::ecdsa::signature::Signer;
use p256::ecdsa::{Signature, SigningKey, VerifyingKey};
use p256::pkcs8::{EncodePrivateKey, EncodePublicKey, LineEnding};
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use tokio::sync::RwLock;
use uuid::Uuid;

#[derive(Clone)]
pub struct IproovServices {
    inner: Arc<Inner>,
}

struct Inner {
    state: RwLock<State>,
    threshold_cents: u64,
}

struct State {
    presentations: HashMap<String, PresentationEntry>,
    carts: HashMap<String, CartSession>,
    keys: GatewayKeys,
}

#[derive(Clone)]
struct GatewayKeys {
    encoding: EncodingKey,
    decoding: DecodingKey,
    signing: SigningKey,
    kid: String,
    jwk: Value,
    issuer: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct PresentationInfo {
    pub request_id: String,
    pub policy: String,
    pub deeplink: String,
    pub qr_code: String,
    pub expires_at: u64,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct DecisionToken {
    pub request_id: String,
    pub decision_jwt: String,
    pub approved: bool,
}

#[derive(Clone)]
struct PresentationEntry {
    record: PresentationRecord,
    decision: Option<DecisionToken>,
}

#[derive(Clone)]
struct PresentationRecord {
    id: String,
    policy: String,
    amount_cents: u64,
    sku: Option<String>,
    metadata: Value,
    created_at: u64,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct CartQuote {
    pub cart_id: String,
    pub merchant_id: String,
    pub merchant_name: String,
    pub items: Vec<CartItem>,
    pub total_cents: u64,
    pub currency: String,
    pub cart_hash: String,
    pub merchant_signature: String,
    pub user_signature_required: bool,
    pub expires_at: u64,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct CartItem {
    pub sku: String,
    pub label: String,
    pub quantity: u32,
    pub unit_price_cents: u64,
}

#[derive(Clone)]
struct CartSession {
    quote: CartQuote,
    status: CartStatus,
    mandate: Option<CartMandate>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CartStatus {
    Pending,
    Approved,
    Rejected,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct CartMandate {
    pub cart_id: String,
    pub cart_hash: String,
    pub approved_at: u64,
    pub approval_expires_at: u64,
    pub signature: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct OrderConfirmation {
    pub order_id: String,
    pub pickup_code: String,
}

impl IproovServices {
    pub fn new(threshold_cents: u64) -> Result<Self> {
        let keys = GatewayKeys::new()?;
        Ok(Self {
            inner: Arc::new(Inner {
                state: RwLock::new(State {
                    presentations: HashMap::new(),
                    carts: HashMap::new(),
                    keys,
                }),
                threshold_cents,
            }),
        })
    }

    pub async fn jwks(&self) -> Value {
        self.inner.state.read().await.keys.jwk.clone()
    }

    pub async fn create_presentation(
        &self,
        policy: String,
        amount_cents: u64,
        sku: Option<String>,
        metadata: Value,
    ) -> Result<PresentationInfo> {
        let request_id = format!("req_{}", Uuid::new_v4());
        let deeplink = format!("iproov://present/{}", request_id);
        let qr_code = format!("QR({})", request_id);
        let expires_at = now_ts() + 15 * 60;

        let record = PresentationRecord {
            id: request_id.clone(),
            policy,
            amount_cents,
            sku,
            metadata,
            created_at: now_ts(),
        };

        let info = PresentationInfo {
            request_id: request_id.clone(),
            policy: record.policy.clone(),
            deeplink,
            qr_code,
            expires_at,
        };

        let mut state = self.inner.state.write().await;
        state.presentations.insert(
            request_id,
            PresentationEntry {
                record,
                decision: None,
            },
        );

        Ok(info)
    }

    pub async fn approve_presentation(
        &self,
        request_id: &str,
        agent_id: &str,
        audience: &str,
    ) -> Result<DecisionToken> {
        let mut state = self.inner.state.write().await;
        let issuer = state.keys.issuer.clone();
        let signing_keys = state.keys.clone();
        let entry = state
            .presentations
            .get_mut(request_id)
            .ok_or_else(|| anyhow!("presentation not found"))?;

        if let Some(existing) = &entry.decision {
            return Ok(existing.clone());
        }

        let claims = DecisionClaims::new(agent_id, audience, &entry.record, &issuer);
        let token = self.sign_decision(&signing_keys, &claims)?;
        let decision = DecisionToken {
            request_id: entry.record.id.clone(),
            decision_jwt: token,
            approved: true,
        };
        entry.decision = Some(decision.clone());
        Ok(decision)
    }

    pub async fn await_decision(&self, request_id: &str) -> Result<Option<DecisionToken>> {
        let state = self.inner.state.read().await;
        Ok(state
            .presentations
            .get(request_id)
            .and_then(|entry| entry.decision.clone()))
    }

    pub async fn introspect_decision(&self, token: &str) -> Result<Value> {
        let state = self.inner.state.read().await;
        let mut validation = Validation::new(Algorithm::ES256);
        validation.set_audience::<&str>(&[]);
        validation.set_issuer(&[state.keys.issuer.clone()]);
        let decoded = decode::<DecisionClaims>(token, &state.keys.decoding, &validation)
            .map_err(|err| anyhow!("decision verify failed: {err}"))?;
        Ok(json!({
            "claims": decoded.claims,
        }))
    }

    pub async fn quote_cart(
        &self,
        term: Option<String>,
        sku: Option<String>,
        quantity: Option<u32>,
    ) -> Result<CartQuote> {
        let catalog = default_catalog();
        let product = select_product(&catalog, term.as_deref(), sku.as_deref());
        let quantity = quantity.unwrap_or(1).max(1);
        let total_cents = product.unit_price_cents * quantity as u64;
        let cart_id = format!("cart_{}", Uuid::new_v4());

        let mut session = CartSession {
            quote: CartQuote {
                cart_id: cart_id.clone(),
                merchant_id: "merchant.example:a2a-gadgets".into(),
                merchant_name: "A2A Gadget Store".into(),
                items: vec![CartItem {
                    sku: product.sku.clone(),
                    label: product.label.clone(),
                    quantity,
                    unit_price_cents: product.unit_price_cents,
                }],
                total_cents,
                currency: "USD".into(),
                cart_hash: String::new(),
                merchant_signature: String::new(),
                user_signature_required: total_cents > self.inner.threshold_cents,
                expires_at: now_ts() + 5 * 60,
            },
            status: CartStatus::Pending,
            mandate: None,
        };

        let canonical = canonicalize(&json!({
            "cart_id": session.quote.cart_id,
            "items": session.quote.items,
            "total_cents": session.quote.total_cents,
            "currency": session.quote.currency,
            "merchant_id": session.quote.merchant_id,
        }));

        let mut state = self.inner.state.write().await;
        let cart_hash = hash_base64(&canonical);
        let merchant_signature = sign_text(&state.keys, &cart_hash)?;
        session.quote.cart_hash = cart_hash;
        session.quote.merchant_signature = merchant_signature;

        let quote = session.quote.clone();
        state.carts.insert(quote.cart_id.clone(), session);
        Ok(quote)
    }

    pub async fn start_cart(&self, cart_id: &str) -> Result<CartQuote> {
        let state = self.inner.state.read().await;
        let session = state
            .carts
            .get(cart_id)
            .ok_or_else(|| anyhow!("cart not found"))?;
        Ok(session.quote.clone())
    }

    pub async fn approve_cart(&self, cart_id: &str) -> Result<CartMandate> {
        let mut state = self.inner.state.write().await;
        let now = now_ts();
        let keys = state.keys.clone();
        let session = state
            .carts
            .get_mut(cart_id)
            .ok_or_else(|| anyhow!("cart not found"))?;
        let signature = sign_text(&keys, &session.quote.cart_hash)?;
        let mandate = CartMandate {
            cart_id: session.quote.cart_id.clone(),
            cart_hash: session.quote.cart_hash.clone(),
            approved_at: now,
            approval_expires_at: now + 300,
            signature,
        };
        session.mandate = Some(mandate.clone());
        session.status = CartStatus::Approved;
        Ok(mandate)
    }

    pub async fn fetch_mandate(&self, cart_id: &str) -> Result<Option<CartMandate>> {
        let state = self.inner.state.read().await;
        Ok(state
            .carts
            .get(cart_id)
            .and_then(|session| session.mandate.clone()))
    }

    pub async fn place_order(
        &self,
        cart_id: &str,
        mandate: Option<CartMandate>,
        decision: Option<String>,
    ) -> Result<OrderConfirmation> {
        let state = self.inner.state.read().await;
        let session = state
            .carts
            .get(cart_id)
            .ok_or_else(|| anyhow!("cart not found"))?;

        if session.quote.user_signature_required {
            let mandate = mandate.ok_or_else(|| anyhow!("mandate required"))?;
            if mandate.cart_hash != session.quote.cart_hash {
                return Err(anyhow!("mandate cart hash mismatch"));
            }
        }

        if let Some(token) = decision {
            let mut validation = Validation::new(Algorithm::ES256);
            validation.set_audience::<&str>(&[]);
            validation.set_issuer(&[state.keys.issuer.clone()]);
            decode::<DecisionClaims>(&token, &state.keys.decoding, &validation)
                .map_err(|err| anyhow!("decision verify failed: {err}"))?;
        }

        drop(state);

        Ok(OrderConfirmation {
            order_id: format!("order-{}", Uuid::new_v4().simple()),
            pickup_code: random_code(4),
        })
    }

    fn sign_decision(&self, keys: &GatewayKeys, claims: &DecisionClaims) -> Result<String> {
        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(keys.kid.clone());
        encode(&header, claims, &keys.encoding).map_err(|err| anyhow!(err))
    }
}

fn sign_text(keys: &GatewayKeys, text: &str) -> Result<String> {
    let signature: Signature = keys.signing.sign(text.as_bytes());
    Ok(URL_SAFE_NO_PAD.encode(signature.to_der()))
}

fn random_code(len: usize) -> String {
    let mut rng = rand::thread_rng();
    (0..len)
        .map(|_| {
            let value: u8 = rng.gen_range(0..10);
            (b'0' + value) as char
        })
        .collect()
}

impl GatewayKeys {
    fn new() -> Result<Self> {
        let mut rng = rand::thread_rng();
        let signing_key = SigningKey::random(&mut rng);
        let verifying_key = signing_key.verifying_key();
        let private_pem = signing_key
            .to_pkcs8_pem(LineEnding::LF)
            .map_err(|err| anyhow!("pem encode failed: {err}"))?;
        let public_pem = verifying_key
            .to_public_key_pem(LineEnding::LF)
            .map_err(|err| anyhow!("pem encode failed: {err}"))?;

        let encoding = EncodingKey::from_ec_pem(private_pem.as_bytes())
            .map_err(|err| anyhow!("encoding key error: {err}"))?;
        let decoding = DecodingKey::from_ec_pem(public_pem.as_bytes())
            .map_err(|err| anyhow!("decoding key error: {err}"))?;

        let point = verifying_key.to_encoded_point(false);
        let x = URL_SAFE_NO_PAD.encode(point.x().unwrap());
        let y = URL_SAFE_NO_PAD.encode(point.y().unwrap());
        let kid = format!("ag-{}", Uuid::new_v4().simple());

        let jwk = json!({
            "keys": [
                {
                    "kty": "EC",
                    "use": "sig",
                    "crv": "P-256",
                    "kid": kid,
                    "alg": "ES256",
                    "x": x,
                    "y": y,
                }
            ]
        });

        Ok(Self {
            encoding,
            decoding,
            signing: signing_key,
            kid,
            jwk,
            issuer: "https://gateway.advatar.local".into(),
        })
    }
}

fn now_ts() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_secs()
}

fn hash_base64(input: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    let digest = hasher.finalize();
    URL_SAFE_NO_PAD.encode(digest)
}

fn canonicalize(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => format!("\"{}\"", s),
        Value::Array(arr) => {
            let inner: Vec<String> = arr.iter().map(canonicalize).collect();
            format!("[{}]", inner.join(","))
        }
        Value::Object(map) => {
            let mut keys: Vec<_> = map.keys().collect();
            keys.sort();
            let parts: Vec<String> = keys
                .into_iter()
                .map(|k| format!("\"{}\":{}", k, canonicalize(&map[k])))
                .collect();
            format!("{{{}}}", parts.join(","))
        }
    }
}

#[derive(Clone)]
struct CatalogProduct {
    sku: String,
    label: String,
    unit_price_cents: u64,
}

fn default_catalog() -> Vec<CatalogProduct> {
    vec![
        CatalogProduct {
            sku: "MBA13-2025".into(),
            label: "MacBook Air 13\" (M3)".into(),
            unit_price_cents: 120_000,
        },
        CatalogProduct {
            sku: "PIXEL9-128".into(),
            label: "Pixel 9 128GB".into(),
            unit_price_cents: 99_900,
        },
        CatalogProduct {
            sku: "PIXELBUDS-PRO".into(),
            label: "Pixel Buds Pro".into(),
            unit_price_cents: 29_900,
        },
    ]
}

fn select_product<'a>(
    catalog: &'a [CatalogProduct],
    term: Option<&str>,
    sku: Option<&str>,
) -> &'a CatalogProduct {
    if let Some(sku) = sku {
        if let Some(product) = catalog.iter().find(|p| p.sku.eq_ignore_ascii_case(sku)) {
            return product;
        }
    }
    if let Some(term) = term {
        let term_lower = term.to_lowercase();
        if let Some(product) = catalog.iter().find(|p| {
            let label = p.label.to_lowercase();
            label.contains(&term_lower) || p.sku.to_lowercase().contains(&term_lower)
        }) {
            return product;
        }
    }
    &catalog[0]
}

#[derive(Debug, Serialize, Deserialize)]
struct DecisionClaims {
    iss: String,
    sub: String,
    aud: String,
    exp: u64,
    iat: u64,
    jti: String,
    request_id: String,
    policy: String,
    amount_cents: u64,
    sku: Option<String>,
}

impl DecisionClaims {
    fn new(agent_id: &str, audience: &str, record: &PresentationRecord, issuer: &str) -> Self {
        let now = now_ts();
        Self {
            iss: issuer.to_string(),
            sub: agent_id.to_string(),
            aud: audience.to_string(),
            exp: now + 300,
            iat: now,
            jti: format!("dec-{}", Uuid::new_v4()),
            request_id: record.id.clone(),
            policy: record.policy.clone(),
            amount_cents: record.amount_cents,
            sku: record.sku.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn presentation_flow_yields_stable_tokens() -> Result<()> {
        let services = IproovServices::new(120_000)?;
        let metadata = json!({ "origin": "unit-test" });
        let info = services
            .create_presentation("policy-1".into(), 45_000, None, metadata)
            .await?;
        assert!(!info.request_id.is_empty());
        assert!(services.await_decision(&info.request_id).await?.is_none());

        let decision = services
            .approve_presentation(&info.request_id, "agent-9", "")
            .await?;
        assert!(decision.approved);

        let snapshot = services.await_decision(&info.request_id).await?;
        assert!(snapshot.is_some());

        let report_err = services
            .introspect_decision(&decision.decision_jwt)
            .await
            .expect_err("introspection enforces audience constraints");
        assert!(report_err.to_string().contains("InvalidAudience"));
        Ok(())
    }

    #[tokio::test]
    async fn cart_flow_enforces_mandate_for_high_value_orders() -> Result<()> {
        let services = IproovServices::new(50_000)?;
        let quote = services
            .quote_cart(None, Some("MBA13-2025".into()), Some(1))
            .await?;
        assert!(quote.user_signature_required);

        let session = services.start_cart(&quote.cart_id).await?;
        assert_eq!(session.cart_id, quote.cart_id);

        let mandate = services.approve_cart(&quote.cart_id).await?;
        assert_eq!(mandate.cart_id, quote.cart_id);

        let fetched = services.fetch_mandate(&quote.cart_id).await?;
        assert!(fetched.is_some());

        let confirmation = services
            .place_order(&quote.cart_id, Some(mandate.clone()), None)
            .await?;
        assert!(confirmation.order_id.starts_with("order-"));
        assert_eq!(confirmation.pickup_code.len(), 4);

        Ok(())
    }

    #[tokio::test]
    async fn placing_high_value_cart_without_mandate_fails() -> Result<()> {
        let services = IproovServices::new(10_000)?;
        let quote = services
            .quote_cart(None, Some("MBA13-2025".into()), Some(1))
            .await?;
        assert!(quote.user_signature_required);

        match services.place_order(&quote.cart_id, None, None).await {
            Ok(_) => panic!("mandate is required for high value orders"),
            Err(err) => assert!(err.to_string().contains("mandate required")),
        }
        Ok(())
    }
}
