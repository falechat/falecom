module Internal
  # Unauthenticated at the app layer — security is the ingress boundary.
  # See ARCHITECTURE.md § Security → /internal/ingest authentication.
  # Still enforced: Channel registration lookup + schema validation.
  class IngestController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_forgery_protection only: :create

    def create
      payload = request.request_parameters
      payload = JSON.parse(request.raw_post) if payload.blank? && request.raw_post.present?

      FaleComChannel::Payload.validate!(payload.transform_keys(&:to_s))

      channel = Channel.find_by(
        channel_type: payload.dig("channel", "type"),
        identifier: payload.dig("channel", "identifier")
      )
      return render_422("unknown_channel") unless channel&.active?

      case payload["type"]
      when "inbound_message"
        message = Ingestion::ProcessMessage.call(channel, payload)
        render json: {status: "ok", message_id: message.id}
      when "outbound_status_update"
        result = Ingestion::ProcessStatusUpdate.call(channel, payload)
        case result
        when :retry then render_422("unknown_external_id")
        else render json: {status: "ok"}
        end
      else
        render_422("unknown_type")
      end
    rescue FaleComChannel::InvalidPayloadError, JSON::ParserError => e
      render_422(e.message)
    end

    private

    def render_422(reason)
      render json: {status: "error", reason: reason}, status: :unprocessable_entity
    end
  end
end
