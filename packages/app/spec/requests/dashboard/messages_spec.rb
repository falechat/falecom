require "rails_helper"

RSpec.describe "Dashboard::Messages", type: :request do
  let(:agent) do
    User.create!(name: "Agent", email_address: "ag-#{SecureRandom.hex(4)}@x.test", password: "password", role: "agent")
  end
  let(:other) do
    User.create!(name: "Other", email_address: "ot-#{SecureRandom.hex(4)}@x.test", password: "password", role: "agent")
  end
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-#{SecureRandom.hex(2)}", name: "WA") }
  let(:contact) { Contact.create!(name: "C") }
  let(:cc) { ContactChannel.create!(channel: channel, contact: contact, source_id: "55119") }
  let(:conversation) do
    channel.conversations.create!(contact: contact, contact_channel: cc, status: "queued",
      display_id: rand(1_000_000), last_activity_at: Time.current, assignee: agent)
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  it "creates an outbound message and enqueues SendMessageJob" do
    sign_in(agent)
    expect {
      post dashboard_conversation_messages_path(conversation),
        params: {message: {content: "hi"}},
        headers: {"Accept" => "text/vnd.turbo-stream.html"}
    }.to change(Message, :count).by(1)
      .and have_enqueued_job(SendMessageJob)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("hi")
  end

  it "rejects empty content with 422" do
    sign_in(agent)
    post dashboard_conversation_messages_path(conversation),
      params: {message: {content: "  "}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 403 when user cannot reply" do
    sign_in(other)
    post dashboard_conversation_messages_path(conversation),
      params: {message: {content: "hi"}}
    expect(response).to have_http_status(:forbidden)
  end

  it "redirects to login when unauthenticated" do
    post dashboard_conversation_messages_path(conversation),
      params: {message: {content: "hi"}}
    expect(response).to redirect_to(new_session_path)
  end
end
