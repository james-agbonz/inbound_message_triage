# Inbound Message Triage Pipeline

This is an automation that handles inbound support messages end to end,it reads the message, figures out what it's about, logs it, and only pulls in a human when something genuinely needs one. Everything else gets handled automatically.

---
## Loom video link
watch the video here;
https://www.loom.com/share/84d2d688347145c3a0dcfd57957537e9


## What it does

A message comes in via webhook. The pipeline then:

1. **Validates** the message — if it's empty or malformed, it gets rejected immediately and logged, no AI call wasted.
2. **Checks for duplicates** — the same message sent twice won't create two rows or two notifications.
3. **Classifies it with AI** — sends the message to Gemini and gets back a structured result: category, urgency, whether a human is needed, and a suggested reply.
4. **Validates the AI's response** — if the model returns something unexpected, the pipeline fails safe: it flags the message for a human rather than dropping it or writing garbage.
5. **Logs everything to Supabase** — every message, including rejects and duplicates, gets a row with a clear status so nothing silently disappears.
6. **Notifies a human if needed** — posts a readable alert (who, what category, urgency, suggested reply) to a webhook endpoint. Only fires when the message is genuinely risky.
7. **Responds to the caller** — returns a clean JSON summary of what happened.

---

## Setup

### 1. Supabase — create the table
Go to your Supabase project → SQL Editor → paste and run `schema.sql`.
This creates the `inbound_messages` table and a view showing today's message volume by category.

Then in n8n, create a **Supabase API** credential using your project URL and service-role key (found under Supabase → Settings → API). Select that credential on the three Supabase nodes in the workflow.

### 2. Set your environment variables
No secrets are hardcoded in the workflow. Before starting n8n, export these in the same terminal:

```bash
export GEMINI_API_KEY="your_google_ai_studio_key"
export NOTIFY_WEBHOOK_URL="https://webhook.site/your-unique-id"
n8n start
```

- **GEMINI_API_KEY** — free from [Google AI Studio](https://aistudio.google.com)
- **NOTIFY_WEBHOOK_URL** — grab a free one at [webhook.site](https://webhook.site)

### 3. Import and activate
Import `inbound_triage_workflow.json` into n8n, connect the Supabase credential, then hit **Activate**.

---

## Test it

```bash
# Normal message — should classify and log with needs_human: false
curl -X POST <YOUR_WEBHOOK_URL> -H 'Content-Type: application/json' \
  -d '{"from":"jane@example.com","channel":"email","message":"What payment methods do you accept?"}'

# Refund complaint — should flag needs_human: true and send a notification
curl -X POST <YOUR_WEBHOOK_URL> -H 'Content-Type: application/json' \
  -d '{"from":"tom@example.com","channel":"email","message":"This course is terrible, I want a full refund or I am disputing the charge."}'

# Broken payload — should return a 400 and log a rejected row
curl -X POST <YOUR_WEBHOOK_URL> -H 'Content-Type: application/json' \
  -d '{"from":"x@example.com","channel":"email","message":""}'
```

---

## Key decisions and why

**Guardrails that fail safe.**
There are two validation layers. The first catches bad input before touching the AI. The second checks that the AI's response has the right shape and valid values. If either check fails, the pipeline doesn't crash or skip the message, it flags it for a human and logs it as `ai_fallback`. The reasoning: a message we couldn't understand is exactly the kind that shouldn't be quietly dropped.

**Structure enforced at the API level.**
The Gemini call uses `responseMimeType: application/json` with a strict `responseSchema` that locks down the allowed values for each field. The model physically can't return the wrong shape, it's not just prompt instructions we're hoping it follows.

**The human flag is two-sided.**
The AI is told specifically when to flag (`needs_human: true`) — refunds, complaints, anger, chargeback threats, and specifically when not to — pricing questions, scheduling, general info. Without the second half, the model tends to over-flag and the human queue loses meaning.

**Everything gets logged.**
Rejected payloads, duplicates, AI fallbacks all get a row in the table with a `status` and an `error_note`. This makes the pipeline auditable: you can always see what came in, what happened to it, and why.

**Idempotency built in.**
Each message gets a fingerprint (a hash of sender + channel + message). If the same message arrives twice, the second one is caught before the AI call and returns the original result instead of creating a duplicate row.

---

## What's next (given more time)

- **Retry logic** on the AI call — backoff on rate limits before falling back to the safe default.
- **Smarter notification routing** — Slack for high urgency, email digest for low.

## What was left out (deliberately)

- **Webhook authentication** — a shared secret or HMAC header would be the first production addition.
- **Slack integration** — webhook.site is used here for zero-setup demos; swapping the Notify node for Slack is a small change.
- **Rate limiting and PII redaction** — important for production, out of scope for this slice.
