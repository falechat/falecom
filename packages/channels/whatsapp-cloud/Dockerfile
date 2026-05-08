FROM ruby:4.0.2-slim

WORKDIR /app

RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# Build context = repo root so the path-dep falecom_channel gem is available.
COPY packages/falecom_channel /falecom_channel
COPY packages/channels/whatsapp-cloud /app

RUN bundle install

EXPOSE 9292
CMD ["bundle", "exec", "ruby", "app.rb"]
