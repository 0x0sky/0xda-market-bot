FROM ruby:3.3.11-slim AS build

WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*
COPY Gemfile ./
RUN bundle install
COPY . .
RUN bundle exec rake

FROM ruby:3.3.11-slim

WORKDIR /app
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

EXPOSE 10000
CMD ["bundle", "exec", "ruby", "bin/start"]
