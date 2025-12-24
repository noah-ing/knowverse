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

ActiveRecord::Schema[8.0].define(version: 2025_12_24_200146) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.bigint "visit_id"
    t.bigint "user_id"
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.bigint "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "cluster_memberships", force: :cascade do |t|
    t.bigint "document_id"
    t.bigint "document_cluster_id"
    t.float "confidence_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_cluster_id"], name: "index_cluster_memberships_on_document_cluster_id"
    t.index ["document_id"], name: "index_cluster_memberships_on_document_id"
  end

  create_table "conversation_messages", force: :cascade do |t|
    t.bigint "conversation_session_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_session_id", "created_at"], name: "idx_conv_msgs_on_conv_session_id_and_created_at"
    t.index ["conversation_session_id"], name: "index_conversation_messages_on_conversation_session_id"
    t.index ["role"], name: "index_conversation_messages_on_role"
  end

  create_table "conversation_sessions", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.boolean "pinned", default: false
    t.jsonb "metadata", default: {}
    t.datetime "last_message_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_message_at"], name: "index_conversation_sessions_on_last_message_at"
    t.index ["organization_id", "user_id"], name: "idx_conversation_sessions_org_use"
    t.index ["organization_id"], name: "index_conversation_sessions_on_organization_id"
    t.index ["user_id"], name: "index_conversation_sessions_on_user_id"
  end

  create_table "document_clusters", force: :cascade do |t|
    t.bigint "organization_id"
    t.string "name"
    t.text "description"
    t.integer "document_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_document_clusters_on_organization_id"
  end

  create_table "document_sources", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.integer "source_type", default: 0, null: false
    t.string "name"
    t.text "credentials"
    t.datetime "last_sync_at"
    t.string "sync_status", default: "disconnected"
    t.text "sync_error"
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_document_sources_on_organization_id"
  end

  create_table "documents", force: :cascade do |t|
    t.string "title"
    t.text "content"
    t.bigint "organization_id"
    t.bigint "user_id"
    t.string "file_path"
    t.string "file_type"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.string "embedding_status", default: "pending"
    t.integer "word_count", default: 0
    t.string "primary_embedding_type"
    t.string "status", default: "pending", null: false
    t.bigint "document_source_id"
    t.string "external_id"
    t.string "external_url"
    t.index ["document_source_id", "external_id"], name: "index_documents_on_document_source_id_and_external_id", unique: true, where: "(document_source_id IS NOT NULL)"
    t.index ["document_source_id"], name: "index_documents_on_document_source_id"
    t.index ["organization_id"], name: "index_documents_on_organization_id"
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "domain_confidence_scores", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "query_text", null: false
    t.string "domain", null: false
    t.float "total_score", null: false
    t.jsonb "factor_scores"
    t.boolean "was_successful"
    t.float "semantic_similarity"
    t.float "corpus_coverage"
    t.float "query_characteristics"
    t.float "historical_performance"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "query_text", "domain"], name: "idx_domain_confidence_scores_org_que_dom"
    t.index ["organization_id"], name: "index_domain_confidence_scores_on_organization_id"
  end

  create_table "domain_embedding_models", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "base_model", null: false
    t.string "domain", null: false
    t.integer "dimension", null: false
    t.string "version"
    t.text "description"
    t.jsonb "configuration", default: {}
    t.jsonb "performance_metrics", default: {}
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_domain_embedding_models_on_domain"
    t.index ["organization_id", "domain"], name: "idx_domain_models_on_org_and_domain"
    t.index ["organization_id", "name"], name: "idx_domain_models_on_org_and_name", unique: true
    t.index ["organization_id"], name: "index_domain_embedding_models_on_organization_id"
  end

  create_table "organization_templates", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.text "description"
    t.text "content", null: false
    t.jsonb "variables", default: {}
    t.jsonb "configuration", default: {}
    t.string "template_type", default: "rag", null: false
    t.boolean "is_default", default: false
    t.integer "usage_count", default: 0
    t.float "average_rating", default: 0.0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_organization_templates_on_organization_id_and_name", unique: true
    t.index ["organization_id", "template_type", "is_default"], name: "idx_org_templates_on_org_type_default"
    t.index ["organization_id"], name: "index_organization_templates_on_organization_id"
  end

  create_table "organization_users", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "viewer", null: false
    t.string "invitation_token"
    t.datetime "invitation_accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "user_id"], name: "index_organization_users_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "index_organization_users_on_organization_id"
    t.index ["user_id"], name: "index_organization_users_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.jsonb "settings"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mcp_api_key"
    t.index ["mcp_api_key"], name: "index_organizations_on_mcp_api_key"
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "plans", force: :cascade do |t|
    t.string "name"
    t.string "stripe_price_id"
    t.integer "amount"
    t.string "interval"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "features", default: [], array: true
  end

  create_table "rag_message_elements", force: :cascade do |t|
    t.bigint "conversation_message_id", null: false
    t.text "content"
    t.integer "token_index"
    t.boolean "complete"
    t.jsonb "source_references"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_message_id"], name: "index_rag_message_elements_on_conversation_message_id"
  end

  create_table "search_feedbacks", id: :serial, force: :cascade do |t|
    t.integer "search_query_id", null: false
    t.integer "document_id", null: false
    t.integer "user_id"
    t.integer "organization_id", null: false
    t.integer "relevance_score", default: 3, null: false
    t.string "feedback_type", null: false
    t.text "comments"
    t.jsonb "metadata"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "idx_search_feedbacks_on_created_at"
    t.index ["document_id"], name: "idx_search_feedbacks_on_document_id"
    t.index ["feedback_type"], name: "idx_search_feedbacks_on_feedback_type"
    t.index ["organization_id"], name: "idx_search_feedbacks_on_organization_id"
    t.index ["relevance_score"], name: "idx_search_feedbacks_on_relevance_score"
    t.index ["search_query_id"], name: "idx_search_feedbacks_on_search_query_id"
    t.index ["user_id"], name: "idx_search_feedbacks_on_user_id"
    t.check_constraint "relevance_score >= 1 AND relevance_score <= 5", name: "search_feedbacks_relevance_score_check"
  end

  create_table "search_queries", id: :serial, force: :cascade do |t|
    t.string "query_text"
    t.string "search_provider"
    t.jsonb "parameters"
    t.float "latency"
    t.integer "result_count"
    t.integer "organization_id", null: false
    t.integer "user_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "idx_search_queries_on_created_at"
    t.index ["organization_id"], name: "idx_search_queries_on_organization_id"
    t.index ["query_text"], name: "idx_search_queries_on_query_text"
    t.index ["search_provider"], name: "idx_search_queries_on_search_provider"
    t.index ["user_id"], name: "idx_search_queries_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sso_configs", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "provider_type", null: false
    t.boolean "enabled", default: false
    t.text "idp_metadata_url"
    t.text "idp_sso_target_url"
    t.text "idp_cert"
    t.string "idp_cert_fingerprint"
    t.string "name_identifier_format", default: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    t.text "issuer"
    t.text "client_id"
    t.text "client_secret"
    t.text "discovery_url"
    t.string "scope", default: "openid email profile"
    t.string "domain_allowlist", default: [], array: true
    t.boolean "auto_provision", default: true
    t.string "default_role", default: "viewer"
    t.datetime "last_used_at"
    t.integer "login_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_sso_configs_on_enabled"
    t.index ["organization_id"], name: "index_sso_configs_on_organization_id", unique: true
    t.index ["provider_type"], name: "index_sso_configs_on_provider_type"
  end

  create_table "streaming_elements", force: :cascade do |t|
    t.bigint "conversation_session_id", null: false
    t.string "token"
    t.integer "token_index"
    t.boolean "complete", default: false
    t.jsonb "source_references"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metadata", default: {}
    t.index ["conversation_session_id"], name: "index_streaming_elements_on_conversation_session_id"
    t.index ["token_index"], name: "index_streaming_elements_on_token_index"
  end

  create_table "template_usages", force: :cascade do |t|
    t.bigint "organization_template_id", null: false
    t.bigint "user_id", null: false
    t.integer "conversation_session_id"
    t.integer "rating"
    t.float "response_time"
    t.integer "token_count"
    t.jsonb "metrics", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_template_id", "created_at"], name: "idx_template_usages_on_org_template_and_date"
    t.index ["organization_template_id"], name: "index_template_usages_on_organization_template_id"
    t.index ["user_id"], name: "index_template_usages_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "login_token"
    t.datetime "login_token_valid_until"
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "card_brand"
    t.string "card_last4"
    t.string "card_exp_month"
    t.string "card_exp_year"
    t.string "subscription_status"
    t.datetime "trial_ends_at"
    t.boolean "admin", default: false, null: false
    t.string "name"
    t.jsonb "notification_preferences", default: {"billing_alerts"=>true, "weekly_summary"=>false, "product_updates"=>true, "marketing_emails"=>false}
    t.string "provider"
    t.string "uid"
    t.bigint "sso_organization_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vector_embeddings", force: :cascade do |t|
    t.bigint "document_id"
    t.string "model"
    t.binary "embedding_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "pending"
    t.text "error_message"
    t.string "embedding_model", default: "base"
    t.integer "dimension", default: 768
    t.string "domain", limit: 255, default: "general"
    t.index ["dimension"], name: "index_vector_embeddings_on_dimension"
    t.index ["document_id"], name: "index_vector_embeddings_on_document_id"
    t.index ["embedding_model"], name: "index_vector_embeddings_on_model_name"
    t.index ["status"], name: "index_vector_embeddings_on_status"
  end

  create_table "vector_projections", force: :cascade do |t|
    t.bigint "document_id"
    t.integer "dimension_count"
    t.binary "projection_data"
    t.string "algorithm"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "vector_embedding_id"
    t.bigint "organization_id"
    t.jsonb "coordinates"
    t.integer "dimensions", default: 3
    t.integer "lod_level", default: 0
    t.jsonb "parameters", default: {}
    t.index ["algorithm", "lod_level"], name: "index_vector_projections_on_algorithm_and_lod_level"
    t.index ["document_id"], name: "index_vector_projections_on_document_id"
    t.index ["organization_id"], name: "index_vector_projections_on_organization_id"
    t.index ["vector_embedding_id"], name: "index_vector_projections_on_vector_embedding_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "conversation_messages", "conversation_sessions"
  add_foreign_key "conversation_sessions", "organizations"
  add_foreign_key "conversation_sessions", "users"
  add_foreign_key "document_sources", "organizations"
  add_foreign_key "documents", "document_sources"
  add_foreign_key "domain_confidence_scores", "organizations"
  add_foreign_key "domain_embedding_models", "organizations"
  add_foreign_key "organization_templates", "organizations"
  add_foreign_key "rag_message_elements", "conversation_messages"
  add_foreign_key "search_feedbacks", "documents", name: "search_feedbacks_document_id_fkey"
  add_foreign_key "search_feedbacks", "organizations", name: "search_feedbacks_organization_id_fkey"
  add_foreign_key "search_feedbacks", "search_queries", name: "search_feedbacks_search_query_id_fkey"
  add_foreign_key "search_feedbacks", "users", name: "search_feedbacks_user_id_fkey"
  add_foreign_key "search_queries", "organizations", name: "search_queries_organization_id_fkey"
  add_foreign_key "search_queries", "users", name: "search_queries_user_id_fkey"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "sso_configs", "organizations"
  add_foreign_key "streaming_elements", "conversation_sessions"
  add_foreign_key "template_usages", "organization_templates"
  add_foreign_key "template_usages", "users"
  add_foreign_key "users", "organizations", column: "sso_organization_id"
  add_foreign_key "vector_projections", "vector_embeddings", on_delete: :cascade
end
