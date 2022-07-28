FROM alpine:latest as builder

ARG http_proxy=http://xxxxxxxxxx:8080
ARG https_proxy=http://xxxxxxxxxx:9443
ARG no_proxy=localhost,127.0.0.1,.xxxxxxxxxx,.xxxxxxxxxx,.xxxxxxxxxx,.xxxxxxxxxx.com,.xxxxxxxxxx.com
ARG node_heap=12228
ARG corp_cert=your-cert.crt

USER root

WORKDIR /root

ENV HTTP_PROXY $http_proxy
ENV HTTPS_PROXY $https_proxy
ENV http_proxy $http_proxy
ENV https_proxy $https_proxy
ENV NO_PROXY $no_proxy
ENV no_proxy $no_proxy
ENV YARN_HTTP_PROXY $http_proxy
ENV YARN_HTTPS_PROXY $https_proxy
ENV NODE_OPTIONS --max-old-space-size=${node_heap}

COPY patch01 /root/patch01
COPY patch02 /root/patch02
COPY patch03 /root/patch03
COPY patch04 /root/patch04
COPY patch05 /root/patch05
COPY patch06 /root/patch06

COPY ${corp_cert} /tmp/cert

RUN cat /tmp/cert >> /etc/ssl/certs/ca-certificates.crt

RUN apk --no-cache add ca-certificates \
    && rm -rf /var/cache/apk/*

COPY ${corp_cert} /usr/local/share/ca-certificates

RUN update-ca-certificates

RUN apk update

RUN apk upgrade

RUN apk --no-cache add bash \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add nodejs \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add npm \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add yarn \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add git \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add go \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add vim \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add make \
    && rm -rf /var/cache/apk/*

RUN apk --no-cache add patch \
    && rm -rf /var/cache/apk/*

RUN yarn config set proxy $http_proxy
RUN yarn config set https-proxy $https_proxy

RUN npm config set proxy $http_proxy
RUN npm config set https-proxy $https_proxy

RUN git config --global http.proxy $http_proxy
RUN git config --global https.proxy $https_proxy

WORKDIR /root 

RUN yarn set version 4.0.0-rc.12

RUN cp .yarn/releases/yarn-4.0.0-rc.12.cjs .

RUN rm -rf .yarn  
RUN rm .yarn* 
RUN rm package.json 

RUN git clone https://github.com/grafana/grafana.git

WORKDIR /root/grafana

RUN git checkout tags/v9.0.5 

RUN cp ../yarn-4.0.0-rc.12.cjs .yarn/releases/ 

RUN patch .yarnrc.yml ../patch01

RUN patch package.json ../patch02

RUN patch packages/grafana-data/package.json ../patch03

RUN patch packages/grafana-schema/package.json ../patch04

RUN patch packages/grafana-ui/package.json ../patch05

RUN patch scripts/cli/tsconfig.json ../patch06

RUN env

RUN yarn install

ENV NODE_ENV production

RUN yarn build      

RUN go mod verify

RUN make build-go

# Final stage
FROM alpine:latest as grafana

ARG http_proxy=http://xxxxxxxxxx:8080
ARG https_proxy=http://xxxxxxxxxx:9443
ARG no_proxy=localhost,127.0.0.1,.xxxxxxxxxx,.xxxxxxxxxx,.xxxxxxxxxx,.xxxxxxxxxx.com,.xxxxxxxxxx.com
ARG corp_cert=your-cert.crt


ENV HTTP_PROXY $http_proxy
ENV HTTPS_PROXY $https_proxy
ENV http_proxy $http_proxy
ENV https_proxy $https_proxy
ENV NO_PROXY $no_proxy
ENV no_proxy $no_proxy

COPY ${corp_cert} /tmp/cert

RUN cat /tmp/cert >> /etc/ssl/certs/ca-certificates.crt

RUN apk --no-cache add ca-certificates \
    && rm -rf /var/cache/apk/*

COPY ${corp_cert} /usr/local/share/ca-certificates

RUN update-ca-certificates

RUN apk update

RUN apk upgrade

LABEL maintainer="You <you@company.com>"

ARG GF_UID="472"
ARG GF_GID="0"

ENV PATH="/usr/share/grafana/bin:$PATH" \
  GF_PATHS_CONFIG="/etc/grafana/grafana.ini" \
  GF_PATHS_DATA="/var/lib/grafana" \
  GF_PATHS_HOME="/usr/share/grafana" \
  GF_PATHS_LOGS="/var/log/grafana" \
  GF_PATHS_PLUGINS="/var/lib/grafana/plugins" \
  GF_PATHS_PROVISIONING="/etc/grafana/provisioning"

WORKDIR $GF_PATHS_HOME

RUN apk add --no-cache ca-certificates bash tzdata musl-utils
RUN apk add --no-cache openssl ncurses-libs ncurses-terminfo-base 
RUN apk upgrade ncurses-libs ncurses-terminfo-base
RUN apk info -vv | sort

COPY --from=builder /root/grafana/conf ./conf

RUN if [ ! $(getent group "$GF_GID") ]; then \
  addgroup -S -g $GF_GID grafana; \
  fi

RUN export GF_GID_NAME=$(getent group $GF_GID | cut -d':' -f1) && \
  mkdir -p "$GF_PATHS_HOME/.aws" && \
  adduser -S -u $GF_UID -G "$GF_GID_NAME" grafana && \
  mkdir -p "$GF_PATHS_PROVISIONING/datasources" \
  "$GF_PATHS_PROVISIONING/dashboards" \
  "$GF_PATHS_PROVISIONING/notifiers" \
  "$GF_PATHS_PROVISIONING/plugins" \
  "$GF_PATHS_PROVISIONING/access-control" \
  "$GF_PATHS_LOGS" \
  "$GF_PATHS_PLUGINS" \
  "$GF_PATHS_DATA" && \
  cp "$GF_PATHS_HOME/conf/sample.ini" "$GF_PATHS_CONFIG" && \
  cp "$GF_PATHS_HOME/conf/ldap.toml" /etc/grafana/ldap.toml && \
  chown -R "grafana:$GF_GID_NAME" "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING" && \
  chmod -R 777 "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING"

COPY --from=builder /root/grafana/bin/*/grafana-server /grafana/bin/*/grafana-cli ./bin/
COPY --from=builder /root/grafana/public ./public
COPY --from=builder /root/grafana/tools ./tools

EXPOSE 3000

COPY --from=builder /root/grafana/packaging/docker/run.sh /run.sh

USER grafana
ENTRYPOINT [ "/run.sh" ]

#CMD /bin/bash

