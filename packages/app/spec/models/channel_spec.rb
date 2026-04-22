require "rails_helper"

RSpec.describe Channel, type: :model do
  let(:valid_attrs) do
    {
      channel_type: "whatsapp_cloud",
      identifier: "5511999999999",
      name: "Test Channel"
    }
  end

  it "validates presence of channel_type, identifier, name" do
    channel = Channel.new
    expect(channel.valid?).to be false
    expect(channel.errors[:channel_type]).not_to be_empty
    expect(channel.errors[:identifier]).not_to be_empty
    expect(channel.errors[:name]).not_to be_empty
  end

  it "defines channel_type enum with whatsapp_cloud, zapi, evolution, instagram, telegram" do
    expect(Channel.channel_types.keys).to eq(%w[whatsapp_cloud zapi evolution instagram telegram])
  end

  it "enforces uniqueness of identifier scoped to channel_type" do
    Channel.create!(valid_attrs)
    duplicate = Channel.new(valid_attrs.merge(name: "Another Channel"))
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "encrypts credentials at rest (ActiveRecord::Encryption)" do
    channel = Channel.create!(valid_attrs.merge(credentials: {access_token: "secret-token-xyz"}))
    raw = Channel.connection.select_value("SELECT credentials FROM channels WHERE id = #{channel.id}")
    expect(raw).not_to include("secret-token-xyz")
    # And the decrypted side still works:
    expect(channel.reload.credentials).to eq("access_token" => "secret-token-xyz")
  end

  it "has many channel_teams and teams through channel_teams" do
    expect(Channel.reflect_on_association(:channel_teams)).not_to be_nil
    expect(Channel.reflect_on_association(:teams)).not_to be_nil
    expect(Channel.reflect_on_association(:teams).macro).to eq(:has_many)
  end

  it "has many contact_channels, conversations" do
    expect(Channel.reflect_on_association(:contact_channels)).not_to be_nil
    expect(Channel.reflect_on_association(:conversations)).not_to be_nil
  end

  it "defaults active to true, auto_assign to false, greeting_enabled to false" do
    channel = Channel.create!(valid_attrs)
    expect(channel.active).to be true
    expect(channel.auto_assign).to be false
    expect(channel.greeting_enabled).to be false
  end

  it "rejects invalid channel_type at the DB level via check constraint" do
    channel = Channel.create!(valid_attrs)
    expect {
      channel.update_column(:channel_type, "bogus_channel")
    }.to raise_error(ActiveRecord::StatementInvalid, /channels_channel_type_check/)
  end

  describe "associations" do
    it "has many messages" do
      association = described_class.reflect_on_association(:messages)
      expect(association).not_to be_nil
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:restrict_with_error)
    end
  end
end
