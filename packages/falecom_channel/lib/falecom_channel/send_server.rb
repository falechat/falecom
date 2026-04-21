require "roda"
require "json"
require "securerandom"

module FaleComChannel
  # Base Roda application for the /send HTTP endpoint.
  #
  # Each channel container subclasses SendServer, sets the HMAC secret via
  # `dispatch_secret`, implements `#handle_send(typed_payload)`, and runs the
  # resulting Rack app.
  #
  # Example:
  #   class WhatsappCloudSendServer < FaleComChannel::SendServer
  #     dispatch_secret ENV.fetch("FALECOM_DISPATCH_HMAC_SECRET")
  #
  #     def handle_send(payload)
  #       # call Meta Graph API …
  #       { external_id: "wamid..." }
  #     end
  #   end
  #
  # run WhatsappCloudSendServer
  class SendServer < Roda
    plugin :json
    plugin :json_parser
    plugin :halt

    # ── Class-level DSL ────────────────────────────────────────────────────────

    class << self
      # Get or set the HMAC secret used to verify /send requests.
      # When called with no argument, walks the superclass chain for the value.
      #
      # @param v [String, nil] secret to store; omit to read
      # @return [String, nil]
      def dispatch_secret(v = nil)
        if v.nil?
          @dispatch_secret || (superclass.respond_to?(:dispatch_secret) ? superclass.dispatch_secret : nil)
        else
          @dispatch_secret = v
        end
      end

      # Get or set the maximum allowed timestamp skew in seconds (default: 300).
      # When called with no argument, walks the superclass chain for the value.
      #
      # @param v [Integer, nil] tolerance in seconds; omit to read
      # @return [Integer]
      def signature_tolerance(v = nil)
        if v.nil?
          @signature_tolerance || (superclass.respond_to?(:signature_tolerance) ? superclass.signature_tolerance : 300)
        else
          @signature_tolerance = v
        end
      end
    end

    # ── Default handle_send (subclasses must override) ─────────────────────────

    # Override in subclasses to dispatch the outbound message to the provider API.
    #
    # @param payload [FaleComChannel::Payload::OutboundMessage] typed payload
    # @return [Hash] result hash to be serialised as the JSON response
    # @raise [NotImplementedError] if not overridden
    def handle_send(_payload)
      raise NotImplementedError, "Subclass must implement #handle_send"
    end

    # ── Routes ─────────────────────────────────────────────────────────────────

    route do |r|
      r.get "health" do
        {"status" => "ok"}
      end

      r.post "send" do
        # Step 1 — Read HMAC headers; halt 401 if missing.
        sig = r.env["HTTP_X_FALECOM_SIGNATURE"]
        r.halt(401, {"error" => "Missing signature header"}) if sig.nil? || sig.empty?

        ts_raw = r.env["HTTP_X_FALECOM_TIMESTAMP"]
        r.halt(401, {"error" => "Missing timestamp header"}) if ts_raw.nil? || ts_raw.empty?

        # Step 2 — Read and rewind raw body (needed for HMAC verification).
        raw = request.body.read
        request.body.rewind

        # Step 3 — Verify HMAC signature.
        begin
          HmacSigner.verify!(
            raw,
            sig,
            ts_raw.to_i,
            self.class.dispatch_secret,
            tolerance: self.class.signature_tolerance
          )
        rescue HmacSigner::InvalidSignatureError => e
          r.halt(401, {"error" => e.message})
        end

        # Determine correlation ID (from header or generate a fresh UUID).
        cid = r.env["HTTP_X_FALECOM_CORRELATION_ID"]
        cid = SecureRandom.uuid if cid.nil? || cid.empty?

        Logging.with_correlation_id(cid) do
          # Step 4 — Parse JSON body.
          payload_hash = begin
            JSON.parse(raw, symbolize_names: true)
          rescue JSON::ParserError
            r.halt(422, {"error" => "Malformed JSON"})
          end

          # Step 5 — Validate payload.
          typed = begin
            Payload.validate!(payload_hash)
          rescue InvalidPayloadError => e
            r.halt(422, {"error" => e.message})
          end

          # Step 6 — Dispatch to #handle_send.
          result = begin
            handle_send(typed)
          rescue => e
            FaleComChannel.logger.error(
              event: "handle_send_failed",
              error: e.message,
              error_class: e.class.name
            )
            r.halt(500, {"error" => e.message})
          end

          FaleComChannel.logger.info(event: "send_dispatched")

          # Step 7 — Return result as JSON (Roda :json plugin serialises Hashes).
          result
        end
      end
    end
  end
end
