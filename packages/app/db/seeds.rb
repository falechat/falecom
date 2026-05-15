# db/seeds.rb
# Idempotent dev dataset for Spec 02.
# Running `bin/rails db:seed` twice must produce no duplicates, no errors,
# and the exact same DB state.

# Skip seeding in test: CI runs `db:prepare` which invokes this file, and seed
# fixtures (e.g. Channel identifier "5511999999999") collide with hardcoded
# values in model specs. The test DB must start empty for transactional
# fixtures to work correctly.
if Rails.env.test?
  puts "== Skipping seeds in test environment =="
  return
end

puts "== Seeding users =="

admin = User.find_or_create_by!(email_address: "admin@falecom.dev") do |u|
  u.name = "Admin User"
  u.role = "admin"
  u.password = "password"
end

supervisor = User.find_or_create_by!(email_address: "supervisor@falecom.dev") do |u|
  u.name = "Supervisor User"
  u.role = "supervisor"
  u.password = "password"
end

agent = User.find_or_create_by!(email_address: "agent@falecom.dev") do |u|
  u.name = "Agent User"
  u.role = "agent"
  u.password = "password"
end

puts "   Users: #{User.count}"

puts "== Seeding teams =="

vendas = Team.find_or_create_by!(name: "Vendas")
suporte = Team.find_or_create_by!(name: "Suporte")

puts "   Teams: #{Team.count}"

puts "== Seeding team memberships =="

TeamMember.find_or_create_by!(team: vendas, user: admin)
TeamMember.find_or_create_by!(team: vendas, user: agent)
TeamMember.find_or_create_by!(team: suporte, user: supervisor)
TeamMember.find_or_create_by!(team: suporte, user: agent)

puts "   TeamMembers: #{TeamMember.count}"

puts "== Seeding channels =="

whatsapp = Channel.find_or_create_by!(channel_type: "whatsapp_cloud", identifier: "5511999999999") do |c|
  c.name = "WhatsApp Vendas"
  c.credentials = {}
  c.auto_assign = true
  c.auto_assign_config = {"strategy" => "round_robin"}
end

zapi = Channel.find_or_create_by!(channel_type: "zapi", identifier: "5511888888888") do |c|
  c.name = "Z-API Suporte"
  c.credentials = {}
end

puts "   Channels: #{Channel.count}"

puts "== Seeding channel teams =="

ChannelTeam.find_or_create_by!(channel: whatsapp, team: vendas)
ChannelTeam.find_or_create_by!(channel: whatsapp, team: suporte)
ChannelTeam.find_or_create_by!(channel: zapi, team: vendas)
ChannelTeam.find_or_create_by!(channel: zapi, team: suporte)

puts "   ChannelTeams: #{ChannelTeam.count}"

puts "== Seeding contacts =="

joao = Contact.find_or_create_by!(name: "João Silva")
maria = Contact.find_or_create_by!(name: "Maria Santos")

puts "   Contacts: #{Contact.count}"

puts "== Seeding contact channels =="

joao_whatsapp = ContactChannel.find_or_create_by!(channel: whatsapp, source_id: "5511987654321") do |cc|
  cc.contact = joao
end

maria_zapi = ContactChannel.find_or_create_by!(channel: zapi, source_id: "5511976543210") do |cc|
  cc.contact = maria
end

puts "   ContactChannels: #{ContactChannel.count}"

puts "== Seeding conversations =="

joao_conv = Conversation.find_or_create_by!(display_id: 1) do |conv|
  conv.channel = whatsapp
  conv.contact = joao
  conv.contact_channel = joao_whatsapp
  conv.status = "queued"
  conv.assignee = agent
  conv.last_activity_at = Time.current
end

maria_conv = Conversation.find_or_create_by!(display_id: 2) do |conv|
  conv.channel = zapi
  conv.contact = maria
  conv.contact_channel = maria_zapi
  conv.status = "queued"
  conv.assignee = agent
  conv.last_activity_at = Time.current
end

puts "   Conversations: #{Conversation.count}"

puts "== Seeding messages =="

if joao_conv.messages.empty?
  Message.create!(
    conversation: joao_conv,
    channel: whatsapp,
    direction: "inbound",
    content: "Olá, gostaria de saber mais sobre os planos disponíveis.",
    status: "received",
    sender_type: "Contact",
    sender_id: joao.id
  )
  Message.create!(
    conversation: joao_conv,
    channel: whatsapp,
    direction: "outbound",
    content: "Olá, João! Seja bem-vindo. Posso te ajudar com informações sobre nossos planos.",
    status: "sent",
    sender_type: "User",
    sender_id: agent.id
  )
  Message.create!(
    conversation: joao_conv,
    channel: whatsapp,
    direction: "inbound",
    content: "Quero saber sobre o plano empresarial.",
    status: "received",
    sender_type: "Contact",
    sender_id: joao.id
  )
  Message.create!(
    conversation: joao_conv,
    channel: whatsapp,
    direction: "outbound",
    content: "Claro! Nosso plano empresarial inclui suporte prioritário e múltiplos canais. Vou te enviar mais detalhes.",
    status: "sent",
    sender_type: "User",
    sender_id: agent.id
  )
end

if maria_conv.messages.empty?
  Message.create!(
    conversation: maria_conv,
    channel: zapi,
    direction: "inbound",
    content: "Boa tarde! Preciso de suporte técnico urgente.",
    status: "received",
    sender_type: "Contact",
    sender_id: maria.id
  )
  Message.create!(
    conversation: maria_conv,
    channel: zapi,
    direction: "outbound",
    content: "Boa tarde, Maria! Pode descrever o problema que está enfrentando?",
    status: "sent",
    sender_type: "User",
    sender_id: agent.id
  )
  Message.create!(
    conversation: maria_conv,
    channel: zapi,
    direction: "inbound",
    content: "O sistema não está conectando desde ontem à noite.",
    status: "received",
    sender_type: "Contact",
    sender_id: maria.id
  )
  Message.create!(
    conversation: maria_conv,
    channel: zapi,
    direction: "outbound",
    content: "Entendi. Vou verificar o status do servidor e retorno em instantes.",
    status: "sent",
    sender_type: "User",
    sender_id: agent.id
  )
  Message.create!(
    conversation: maria_conv,
    channel: zapi,
    direction: "outbound",
    content: "Maria, identificamos o problema. Nosso time técnico está trabalhando na solução. Prazo estimado: 2 horas.",
    status: "sent",
    sender_type: "User",
    sender_id: agent.id
  )
end

puts "   Messages: #{Message.count}"

puts "== Seeding 'Atendimento Vendas' flow =="

flow = Flow.find_or_create_by!(name: "Atendimento Vendas") do |f|
  f.description = "Bot inicial de triagem"
  f.is_active = true
  f.inactivity_threshold_hours = 24
end

if flow.flow_nodes.empty?
  greeting = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Olá! Bem-vindo ao FaleCom Dev."})
  collect = FlowNode.create!(flow: flow, node_type: "collect", content: {"text" => "Qual seu nome?", "variable" => "contact_name", "validation" => "any"})
  short_greeting = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Bem-vindo de volta!"})

  handoff_vendas = FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => vendas.id, "message" => "Transferindo para Vendas...", "assign_collected_name" => true})
  handoff_suporte = FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => suporte.id, "message" => "Transferindo para Suporte...", "assign_collected_name" => true})
  handoff_outros = FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => vendas.id, "message" => "Alguém vai te ajudar em breve!", "assign_collected_name" => true})

  menu = FlowNode.create!(flow: flow, node_type: "menu", content: {
    "text" => "Como posso ajudar?",
    "options" => [
      {"key" => "1", "label" => "Vendas", "next_node_id" => handoff_vendas.id},
      {"key" => "2", "label" => "Suporte", "next_node_id" => handoff_suporte.id},
      {"key" => "3", "label" => "Outros", "next_node_id" => handoff_outros.id}
    ]
  })

  greeting.update!(next_node: collect)
  collect.update!(next_node: menu)
  flow.update!(root_node: greeting, short_greeting_node: short_greeting)
end

if (wa = Channel.find_by(channel_type: "whatsapp_cloud"))
  wa.update!(active_flow: flow) if wa.active_flow_id != flow.id
end

puts "   FlowNodes: #{FlowNode.count}"

puts ""
puts "== Seed complete =="
puts "   Users:           #{User.count}"
puts "   Teams:           #{Team.count}"
puts "   TeamMembers:     #{TeamMember.count}"
puts "   Channels:        #{Channel.count}"
puts "   ChannelTeams:    #{ChannelTeam.count}"
puts "   Contacts:        #{Contact.count}"
puts "   ContactChannels: #{ContactChannel.count}"
puts "   Conversations:   #{Conversation.count}"
puts "   Messages:        #{Message.count}"
puts "   AutomationRules: #{AutomationRule.count}"
puts "   Events:          #{Event.count}"
