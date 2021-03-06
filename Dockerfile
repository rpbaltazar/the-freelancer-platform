FROM ruby:2.6.3-stretch as base

# WORKDIR needs to be the same as in the final base image or compiled gems will point to an invalid directory
# NOTE: For the compiled gems to be shared across services then the WORKDIR needs to be same for all images
RUN mkdir -p /home/rails/services/app
WORKDIR /home/rails/services/app

# Install gems that need compiling first b/c they can take a long time to compile
RUN gem install \
    bundler:2.0.1 \
    nokogiri:1.10.3 \
    ffi:1.10.0 \
    mini_portile2:2.3.0 \
    msgpack:1.2.9 \
    pg:1.1.4 \
    nio4r:2.3.1 \
    puma:3.12.0 \
    eventmachine:1.2.7

ARG ROS_DIR=./ros
ARG project=user
COPY services/${project}/Gemfile* ./
# NOTE: Dependent gem's gemspecs need to be copied in so that their dependencies are also installed
COPY ${ROS_DIR}/lib/core/*.gemspec ../../${ROS_DIR}/lib/core/
COPY ${ROS_DIR}/lib/sdk/*.gemspec ../../${ROS_DIR}/lib/sdk/
COPY lib/core/*.gemspec ../../lib/core/
COPY lib/sdk/*.gemspec ../../lib/sdk/

# Remove reference to gems loaded from a path so bundle doesn't blow up
# RUN sed -i '/path/d' Gemfile

# # Don't use the --deployment flag since this is a container. See: http://bundler.io/man/bundle-install.1.html#DEPLOYMENT-MODE
ARG bundle_string='--without development test'
RUN bundle install ${bundle_string} \
 && find /usr/local/bundle -iname '*.o' -exec rm -rf {} \; \
 && find /usr/local/bundle -iname '*.a' -exec rm -rf {} \;

# Runtime container
FROM ruby:2.6.3-slim-stretch

# Install OS packages and create a non-root user to run the application
# To compile pg gem: libpq-dev
# To install pg client to run via bash: postgresql-client
ARG os_packages='libpq5 git less'

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends ${os_packages} \
 && apt-get clean

ARG PUID=1000
ARG PGID=1000

RUN addgroup --gid ${PGID} rails \
 && useradd -ms /bin/bash -d /home/rails --uid ${PUID} --gid ${PGID} rails \
 && mkdir -p /home/rails/services/app \
 && echo 'set editing-mode vi' > /home/rails/.inputrc \
 && echo "alias rspec='spring rspec $@'\nalias src='ss; rc'\nalias ss='spring stop'\nalias rs='rails server -b 0.0.0.0 --pid /tmp/server.pid'\nalias rc='spring rails console'\nalias rk='spring rake'" > /home/rails/.bash_aliases \
 && chown rails:rails /home/rails -R \
 && echo 'rails ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

COPY --chown=rails:rails --from=base /usr/local/bundle /usr/local/bundle

# Rails operations
WORKDIR /home/rails/services/app

ARG project=user
ARG ROS_DIR=./ros
COPY --chown=rails:rails ${ROS_DIR}/lib/core/. ../../${ROS_DIR}/lib/core/
COPY --chown=rails:rails ${ROS_DIR}/lib/sdk/. ../../${ROS_DIR}/lib/sdk/
COPY --chown=rails:rails lib/core/. ../../lib/core/
COPY --chown=rails:rails lib/sdk/. ../../lib/sdk/

COPY --chown=rails:rails services/${project}/. ./

ARG rails_env=production
ENV RAILS_ENV=${rails_env} EDITOR=vim TERM=xterm RAILS_LOG_TO_STDOUT=yes
EXPOSE 3000

USER ${PUID}:${PGID}

# Boot the application; Override this from the command line in order to run other tools
# CMD ["bundle", "exec", "puma", "config.ru"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-P", "/tmp/server.pid"]
