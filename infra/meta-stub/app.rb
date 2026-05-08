require "roda"
require "json"
require "securerandom"
require_relative "lib/webhook_builder"
require_relative "lib/dev_webhook_pusher"

module MetaStub
end

class MetaStub::Server < Roda
  plugin :json
  plugin :json_parser
  plugin :common_logger
  plugin :public, root: File.expand_path("public", __dir__) if File.directory?(File.expand_path("public", __dir__))

  route do |r|
    r.get "health" do
      {"status" => "ok"}
    end

    # Fakes Meta's outbound /messages endpoint (called by WhatsappCloud::Sender).
    r.on "v21.0", String, "messages" do |_phone_number_id|
      r.post do
        {messages: [{id: "wamid.test-#{SecureRandom.hex(4)}"}]}
      end
    end

    # ── Provider simulator endpoints ───────────────────────────────────────
    # POST a Meta-shaped webhook to dev-webhook so the inbound half of the
    # pipeline runs end-to-end without a real Meta account.
    r.on "simulate" do
      pusher = MetaStub::DevWebhookPusher.new

      r.post "inbound" do
        params = JSON.parse(r.body.read)
        payload = MetaStub::WebhookBuilder.inbound_text(
          phone_number_id: params.fetch("phone_number_id"),
          source_id: params.fetch("source_id"),
          content: params.fetch("content"),
          contact_name: params["contact_name"] || "Sim Tester"
        )
        res = pusher.push(payload)
        response.status = res.code.to_i
        {forwarded_to: "dev-webhook", status: res.code, body: safe_parse(res.body), payload: payload}
      end

      r.post "status" do
        params = JSON.parse(r.body.read)
        payload = MetaStub::WebhookBuilder.outbound_status(
          phone_number_id: params.fetch("phone_number_id"),
          external_id: params.fetch("external_id"),
          status: params.fetch("status")
        )
        res = pusher.push(payload)
        response.status = res.code.to_i
        {forwarded_to: "dev-webhook", status: res.code, body: safe_parse(res.body), payload: payload}
      end
    end

    # Tiny HTML form so a human can drive the simulator without curl.
    r.root do
      response["Content-Type"] = "text/html; charset=utf-8"
      INDEX_HTML
    end
  end

  def safe_parse(body)
    JSON.parse(body)
  rescue
    body.to_s
  end

  INDEX_HTML = <<~HTML.freeze
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>FaleCom — Meta Stub Simulator</title>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; }
        fieldset { margin-bottom: 1.5rem; padding: 1rem; }
        label { display: block; margin: 0.5rem 0 0.25rem; font-size: 0.85rem; color: #555; }
        input, textarea, select { width: 100%; padding: 0.5rem; font: inherit; box-sizing: border-box; }
        button { padding: 0.6rem 1.2rem; font: inherit; cursor: pointer; }
        pre { background: #f4f4f4; padding: 1rem; overflow: auto; max-height: 12rem; }
      </style>
    </head>
    <body>
      <h1>Meta Stub Simulator</h1>
      <p>Drives the FaleCom inbound pipeline without a real Meta account. Webhook is signed with <code>WHATSAPP_APP_SECRET</code> and POSTed to <code>dev-webhook</code>.</p>

      <fieldset>
        <legend>Inbound message (contact → agent)</legend>
        <form id="inbound">
          <label>Phone number id (channel.identifier)</label>
          <input name="phone_number_id" value="15550000001" />
          <label>From (source_id, contact's wa_id)</label>
          <input name="source_id" value="5511988888888" />
          <label>Contact name</label>
          <input name="contact_name" value="Sim Tester" />
          <label>Content</label>
          <textarea name="content" rows="3">Olá, vim do simulator</textarea>
          <button type="submit">Send inbound</button>
        </form>
      </fieldset>

      <fieldset>
        <legend>Outbound status update (provider → agent's checkmarks)</legend>
        <form id="status">
          <label>Phone number id</label>
          <input name="phone_number_id" value="15550000001" />
          <label>External id (wamid.* of an outbound message)</label>
          <input name="external_id" value="" />
          <label>Status</label>
          <select name="status">
            <option>sent</option>
            <option>delivered</option>
            <option>read</option>
            <option>failed</option>
          </select>
          <button type="submit">Send status</button>
        </form>
      </fieldset>

      <h3>Result</h3>
      <pre id="out">—</pre>

      <script>
        async function submitForm(formId, path) {
          const form = document.getElementById(formId);
          form.addEventListener("submit", async (e) => {
            e.preventDefault();
            const data = Object.fromEntries(new FormData(form));
            const res = await fetch(path, {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(data)});
            document.getElementById("out").textContent = JSON.stringify(await res.json(), null, 2);
          });
        }
        submitForm("inbound", "/simulate/inbound");
        submitForm("status", "/simulate/status");
      </script>
    </body>
    </html>
  HTML
end
