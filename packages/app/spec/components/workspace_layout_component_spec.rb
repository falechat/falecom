require "rails_helper"

RSpec.describe WorkspaceLayoutComponent, type: :component do
  it "renders the three slots" do
    html = render_inline(described_class.new) do |c|
      c.with_list { "LIST" }
      c.with_main { "MAIN" }
      c.with_sidebar { "SIDEBAR" }
    end
    expect(html.text).to include("LIST")
    expect(html.text).to include("MAIN")
    expect(html.text).to include("SIDEBAR")
  end
end
