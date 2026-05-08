FROM ruby:4.0.2-slim

WORKDIR /app
COPY . .

RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*
RUN bundle install

EXPOSE 4001
CMD ["bundle", "exec", "puma", "-p", "4001", "config.ru"]
