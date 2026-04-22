FROM ruby:4.0.2-slim

WORKDIR /app
COPY Gemfile ./
RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*
RUN bundle install

COPY . .

EXPOSE 4000
CMD ["bundle", "exec", "puma", "-p", "4000", "config.ru"]
