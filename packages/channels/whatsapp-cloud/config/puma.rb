port ENV.fetch("PORT", 9292)
threads ENV.fetch("PUMA_MIN_THREADS", 1).to_i, ENV.fetch("PUMA_MAX_THREADS", 5).to_i
workers ENV.fetch("PUMA_WORKERS", 1).to_i
preload_app! if ENV.fetch("PUMA_WORKERS", 1).to_i > 1
