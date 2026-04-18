# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let!(:user) do
    User.create!(
      email_address: "dashboard-spec@falecom.test",
      password: "spec-password-123",
      password_confirmation: "spec-password-123"
    )
  end

  describe "GET /" do
    context "unauthenticated" do
      it "redirects to the login page" do
        get root_path
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "authenticated" do
      before do
        post session_path, params: {
          email_address: user.email_address,
          password: "spec-password-123"
        }
      end

      it "renders the dashboard shell" do
        get root_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Welcome to FaleCom")
        expect(response.body).to include(user.email_address)
      end
    end
  end
end
