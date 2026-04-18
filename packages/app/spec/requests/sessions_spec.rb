# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let!(:user) do
    User.create!(
      email_address: "spec-user@falecom.test",
      password: "spec-password-123",
      password_confirmation: "spec-password-123"
    )
  end

  describe "GET /session/new" do
    it "renders the login form" do
      get new_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email_address")
      expect(response.body).to include("password")
      expect(response.body).to include("Sign in")
    end
  end

  describe "POST /session" do
    it "signs in with valid credentials" do
      post session_path, params: {
        email_address: user.email_address,
        password: "spec-password-123"
      }
      expect(response).to redirect_to(root_path)
    end

    it "rejects invalid credentials" do
      post session_path, params: {
        email_address: user.email_address,
        password: "wrong-password"
      }
      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to match(/try another|try again|invalid/i)
    end
  end

  describe "DELETE /session" do
    before do
      post session_path, params: {
        email_address: user.email_address,
        password: "spec-password-123"
      }
    end

    it "signs out" do
      delete session_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
