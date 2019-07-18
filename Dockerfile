FROM ruby:2.6.3-slim-stretch

# Create application directory and set it as the WORKDIR.
ENV APP_HOME /usr/src/app
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

COPY src $APP_HOME

RUN bundle install --system --binstubs

CMD ruby aws_ecs_auditor.rb
