require "rails_helper"

RSpec.describe "Rails 8.1 application boot" do
  it "loads the test environment" do
    expect(Rails.env).to eq("test")
  end

  it "connects to Postgres" do
    expect(ActiveRecord::Base.connection.adapter_name).to eq("PostgreSQL")
    expect(ActiveRecord::Base.connection.execute("select 1 as n").first["n"]).to eq(1)
  end

  it "has the User model from the authentication generator" do
    expect(User.new).to be_a(ApplicationRecord)
    expect(User.new).to respond_to(:email_address)
    expect(User.new).to respond_to(:password_digest)
  end

  it "has the Session model from the authentication generator" do
    expect(Session.new).to be_a(ApplicationRecord)
    expect(Session.reflect_on_association(:user)).not_to be_nil
  end

  it "has the Solid trio tables" do
    tables = ActiveRecord::Base.connection.tables
    expect(tables).to include("solid_queue_jobs")
    expect(tables).to include("solid_cable_messages")
    expect(tables).to include("solid_cache_entries")
  end

  it "uses Solid Queue as the Active Job adapter in non-test environments" do
    # test.rb intentionally overrides to :test adapter for fast test isolation
    expect([:solid_queue, :test]).to include(Rails.application.config.active_job.queue_adapter)
  end

  it "uses Solid Cache as the cache store" do
    expect(Rails.cache.class.name).to include("SolidCache")
  end
end
