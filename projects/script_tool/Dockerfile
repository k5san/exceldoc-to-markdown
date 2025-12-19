# syntax=docker/dockerfile:1.7

FROM almalinux:9 AS builder

ARG ENTRY_PACKAGE
RUN test -n "$ENTRY_PACKAGE" || { echo >&2 "ENTRY_PACKAGE is required. pass --build-arg ENTRY_PACKAGE=<name>"; exit 2; }

ARG TARGET="projects/${ENTRY_PACKAGE}"
ENV ENTRY_PACKAGE="${ENTRY_PACKAGE}" \
    TARGET="${TARGET}"

RUN --mount=type=cache,target=/var/cache/dnf \
    --mount=type=cache,target=/var/lib/dnf \
    dnf -y install \
      python3.11 python3.11-devel python3.11-pip \
      gcc make which ca-certificates findutils git \
    && dnf clean all

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL=/usr/local/bin sh

WORKDIR /src

# 依存定義のみ
COPY ./pyproject.toml /src/
COPY ./projects/common_lib/pyproject.toml /src/projects/common_lib/
COPY ./${TARGET}/pyproject.toml /src/${TARGET}/

WORKDIR /src/${TARGET}
RUN --mount=type=cache,target=/root/.cache/uv \
    uv python pin 3.11 \
 && uv sync --frozen || uv sync

# 残りのソース + build.spec
WORKDIR /src
COPY . /src/
COPY ./projects/${ENTRY_PACKAGE}/build.spec /src/${TARGET}/

# ★ build.spec でビルド（--specpath は付けない）
WORKDIR /src/${TARGET}
RUN --mount=type=cache,target=/root/.cache/uv \
    uv add --dev pyinstaller \
 && uv run pyinstaller \
      --distpath /opt/out \
      --workpath /opt/build \
      build.spec \
 # 出力（/opt/out/<module>/<module>）を /opt/out/app に正規化
 && sh -euxc 'out="$(find /opt/out -maxdepth 2 -type f | head -n1)"; test -f "$out"; mv "$out" /opt/out/app'

FROM almalinux:9-minimal AS runtime
WORKDIR /app
COPY --from=builder /opt/out/app /app/app
ENTRYPOINT ["/app/app"]
