# Earshot: the Flutter web app and the Dart server in one image.
#
#   docker build -t earshot .
#   docker run -p 8095:8095 -v earshot-data:/data \
#     -e PUBLIC_BASE_URL=http://localhost:8095 earshot
#
# Configuration is environment variables only. SQLite lives in /data.

FROM debian:bookworm-slim AS web
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.44.2
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}
ENV ANDROID_HOME=/opt/android-sdk
ENV TAR_OPTIONS=--no-same-owner
RUN mkdir -p $ANDROID_HOME
RUN flutter config --no-analytics --no-cli-animations --enable-web --no-enable-android --no-enable-ios
WORKDIR /src
COPY packages/sui_wallet_web/ packages/sui_wallet_web/
COPY packages/upload_recovery/ packages/upload_recovery/
COPY app/pubspec.yaml app/pubspec.lock app/
RUN cd app && flutter pub get
COPY app/ app/
RUN cd app && flutter build web --release --no-web-resources-cdn --no-wasm-dry-run

# 2. Server, compiled to a native executable.
FROM dart:3.12.2 AS server
WORKDIR /src
COPY packages/sui_auth/ packages/sui_auth/
COPY packages/walrus_blob_check/ packages/walrus_blob_check/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get
COPY server/ server/
RUN mkdir -p /out \
 && cd server \
 && dart compile exe bin/server.dart -o /out/earshot-server

# 3. Small runtime with the system SQLite library.
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 \
 && ln -s "$(ls /usr/lib/*-linux-gnu/libsqlite3.so.0)" /usr/lib/libsqlite3.so \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /data && chown nobody:nogroup /data
WORKDIR /app
COPY --from=server /out/earshot-server /app/earshot-server
COPY --from=web /src/app/build/web /app/web
COPY landing/ /app/landing
ENV PORT=8095 \
    DATA_DIR=/data
VOLUME /data
EXPOSE 8095
USER nobody
CMD ["/app/earshot-server"]
