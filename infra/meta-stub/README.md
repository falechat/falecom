# meta-stub

Dev-only fake Meta WhatsApp Cloud API. Two jobs:

1. **Outbound sink.** Fakes Meta's `POST /v21.0/:phone_number_id/messages` so `WhatsappCloud::Sender` (running in `channel-whatsapp-cloud`) can send messages without a real Meta account. Returns canned `wamid.test-*` ids.
2. **Inbound simulator.** Forwards Meta-shaped webhooks to `dev-webhook` with a valid `X-Hub-Signature-256`, exercising the real ingestion pipeline end-to-end without needing a Meta dev portal.

## Running it

Booted by `docker compose up`. Compose also wires `WHATSAPP_APP_SECRET` to the same value used by `channel-whatsapp-cloud-consumer` so signatures verify.

Health: <http://localhost:4001/health>

## Simulator endpoints

### `POST /simulate/inbound`

Builds a Meta `messages` webhook for a single inbound text message, signs it, POSTs to `dev-webhook`. Triggers the full pipeline: `dev-webhook → SQS → channel-whatsapp-cloud-consumer → POST /internal/ingest → DB → Turbo Stream`.

```bash
curl -X POST http://localhost:4001/simulate/inbound \
  -H 'Content-Type: application/json' \
  -d '{"phone_number_id":"15550000001","source_id":"5511988888888","content":"oi do simulator"}'
```

`phone_number_id` must match a `Channel.identifier` of an active `whatsapp_cloud` channel (see seeds). `source_id` is the contact's `wa_id` — any value works; `Contacts::Resolve` will create a contact on first sight.

### `POST /simulate/status`

Builds a Meta `statuses` webhook for an outbound message and forwards it. Useful for testing checkmark progression (Plan 05d).

```bash
curl -X POST http://localhost:4001/simulate/status \
  -H 'Content-Type: application/json' \
  -d '{"phone_number_id":"15550000001","external_id":"wamid.test-abcd","status":"delivered"}'
```

`external_id` is the `Message.external_id` returned when an outbound message was sent through `channel-whatsapp-cloud`.

### Browser UI

`GET /` (e.g. <http://localhost:4001>) renders a tiny HTML form covering both endpoints — for clicking around without curl.

## Outbound sink

Used automatically by the WhatsApp container when `META_API_BASE=http://meta-stub:4001` is set (the default in compose). No manual call needed.

## Going beyond stub: real Meta test number

For smoke testing real Meta semantics (template approval, real rate limits, real error shapes):

1. Create a Meta Developer account at <https://developers.facebook.com>.
2. Create a "WhatsApp Business" app. The "API Setup" tab gives a free test phone number, a temporary 24-hour access token, and a list of up to 5 whitelisted recipient numbers.
3. Generate a long-lived **system user** access token (also free in the test app).
4. Replace the `Channel.credentials` in your dev seed with `{access_token: "<token>", phone_number_id: "<test_pn_id>"}`.
5. Unset `META_API_BASE` in the channel container so `WhatsappCloud::Sender` hits real Meta.

This is for manual smoke only — CI keeps using meta-stub.
