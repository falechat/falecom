# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_21_165955) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "automation_rules", force: :cascade do |t|
    t.jsonb "actions", default: [], null: false
    t.boolean "active", default: true, null: false
    t.jsonb "conditions", default: [], null: false
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.datetime "updated_at", null: false
    t.index ["event_name", "active"], name: "index_automation_rules_on_event_name_and_active"
  end

  create_table "channel_teams", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "team_id"], name: "index_channel_teams_on_channel_id_and_team_id", unique: true
    t.index ["channel_id"], name: "index_channel_teams_on_channel_id"
    t.index ["team_id"], name: "index_channel_teams_on_team_id"
  end

  create_table "channels", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "active_flow_id"
    t.boolean "auto_assign", default: false, null: false
    t.jsonb "auto_assign_config", default: {}, null: false
    t.string "channel_type", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "credentials", default: "{}", null: false
    t.boolean "greeting_enabled", default: false, null: false
    t.text "greeting_message"
    t.string "identifier", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_channels_on_active"
    t.index ["channel_type", "identifier"], name: "index_channels_on_channel_type_and_identifier", unique: true
    t.check_constraint "channel_type::text = ANY (ARRAY['whatsapp_cloud'::character varying, 'zapi'::character varying, 'evolution'::character varying, 'instagram'::character varying, 'telegram'::character varying]::text[])", name: "channels_channel_type_check"
  end

  create_table "contact_channels", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "contact_id", null: false
    t.datetime "created_at", null: false
    t.string "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "source_id"], name: "index_contact_channels_on_channel_id_and_source_id", unique: true
    t.index ["channel_id"], name: "index_contact_channels_on_channel_id"
    t.index ["contact_id"], name: "index_contact_channels_on_contact_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.jsonb "additional_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "identifier"
    t.string "name"
    t.string "phone_number"
    t.datetime "updated_at", null: false
  end

  create_table "conversations", force: :cascade do |t|
    t.jsonb "additional_attributes", default: {}, null: false
    t.bigint "assignee_id"
    t.bigint "channel_id", null: false
    t.bigint "contact_channel_id", null: false
    t.bigint "contact_id", null: false
    t.datetime "created_at", null: false
    t.integer "display_id", null: false
    t.datetime "last_activity_at"
    t.string "status", default: "bot", null: false
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.index ["assignee_id", "status"], name: "index_conversations_on_assignee_id_and_status"
    t.index ["assignee_id"], name: "index_conversations_on_assignee_id"
    t.index ["channel_id", "status"], name: "index_conversations_on_channel_id_and_status"
    t.index ["channel_id"], name: "index_conversations_on_channel_id"
    t.index ["contact_channel_id"], name: "index_conversations_on_contact_channel_id"
    t.index ["contact_channel_id"], name: "index_conversations_open_per_contact_channel", unique: true, where: "((status)::text <> 'resolved'::text)"
    t.index ["contact_id"], name: "index_conversations_on_contact_id"
    t.index ["display_id"], name: "index_conversations_on_display_id", unique: true
    t.index ["status", "last_activity_at"], name: "index_conversations_on_status_and_last_activity_at", order: {last_activity_at: :desc}
    t.index ["team_id", "status"], name: "index_conversations_on_team_id_and_status"
    t.index ["team_id"], name: "index_conversations_on_team_id"
    t.check_constraint "status::text = ANY (ARRAY['bot'::character varying, 'queued'::character varying, 'assigned'::character varying, 'resolved'::character varying]::text[])", name: "conversations_status_check"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.index ["actor_type", "actor_id", "created_at"], name: "index_events_on_actor_type_and_actor_id_and_created_at", order: {created_at: :desc}
    t.index ["created_at"], name: "index_events_on_created_at", order: :desc
    t.index ["name", "created_at"], name: "index_events_on_name_and_created_at", order: {created_at: :desc}
    t.index ["subject_type", "subject_id", "created_at"], name: "index_events_on_subject_type_and_subject_id_and_created_at", order: {created_at: :desc}
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.text "content"
    t.string "content_type", default: "text", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.text "error"
    t.string "external_id"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "raw"
    t.string "reply_to_external_id"
    t.bigint "sender_id"
    t.string "sender_type"
    t.datetime "sent_at"
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "external_id"], name: "index_messages_on_channel_id_and_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["channel_id"], name: "index_messages_on_channel_id"
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender_type_and_sender_id"
    t.check_constraint "content_type::text = ANY (ARRAY['text'::character varying, 'image'::character varying, 'audio'::character varying, 'video'::character varying, 'document'::character varying, 'location'::character varying, 'contact_card'::character varying, 'input_select'::character varying, 'button_reply'::character varying, 'template'::character varying]::text[])", name: "messages_content_type_check"
    t.check_constraint "direction::text = ANY (ARRAY['inbound'::character varying, 'outbound'::character varying]::text[])", name: "messages_direction_check"
    t.check_constraint "status::text = ANY (ARRAY['received'::character varying, 'pending'::character varying, 'sent'::character varying, 'delivered'::character varying, 'read'::character varying, 'failed'::character varying]::text[])", name: "messages_status_check"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "team_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "availability", default: "offline", null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "availability::text = ANY (ARRAY['online'::character varying, 'busy'::character varying, 'offline'::character varying]::text[])", name: "users_availability_check"
    t.check_constraint "role::text = ANY (ARRAY['admin'::character varying, 'supervisor'::character varying, 'agent'::character varying]::text[])", name: "users_role_check"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "channel_teams", "channels"
  add_foreign_key "channel_teams", "teams"
  add_foreign_key "contact_channels", "channels"
  add_foreign_key "contact_channels", "contacts"
  add_foreign_key "conversations", "channels"
  add_foreign_key "conversations", "contact_channels"
  add_foreign_key "conversations", "contacts"
  add_foreign_key "conversations", "teams"
  add_foreign_key "conversations", "users", column: "assignee_id"
  add_foreign_key "messages", "channels"
  add_foreign_key "messages", "conversations"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "team_members", "teams"
  add_foreign_key "team_members", "users"
end
