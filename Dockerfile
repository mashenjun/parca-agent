FROM docker.io/golang:1.18.3-bullseye@sha256:db42e4bb1a7f32da1ec430906769dbbabe9f1868bd4170751e4923f1b8948a45 AS build

# renovate: datasource:github-releases depName=rust-lang/rustup
ARG RUSTUP_VERSION=1.24.3

# For more information about the snapshots, see: https://snapshot.debian.org/
RUN printf '\
deb http://snapshot.debian.org/archive/debian/20220420T025302Z bullseye main\n\
deb http://snapshot.debian.org/archive/debian/20220420T025302Z bullseye-updates main\n\
deb http://snapshot.debian.org/archive/debian/20220420T025302Z bullseye-backports main\n\
deb http://snapshot.debian.org/archive/debian-security/20220420T025302Z bullseye-security main\n\
deb http://snapshot.debian.org/archive/debian/20220420T025302Z sid main\n\
' > /etc/apt/sources.list

# NOTICE: -o Acquire::Check-Valid-Until="false" added as a mitigation,
# see https://github.com/parca-dev/parca-agent/issues/10 for further details.
# hadolint ignore=DL3008
RUN apt-get -o Acquire::Check-Valid-Until="false" update -y && \
    apt-get install --no-install-recommends -yq \
        llvm-14-dev \
        libclang-14-dev \
        clang-14 \
        make \
        gcc \
        coreutils \
        zlib1g-dev \
        libelf-dev \
        ca-certificates \
        netbase && \
    ln -s /usr/bin/clang-14 /usr/bin/clang && \
    ln -s /usr/bin/llc-14 /usr/bin/llc

WORKDIR /parca-agent

# Install Rust
COPY rust-toolchain.toml /parca-agent
# SHELL is not supported for OCI image format
# https://github.com/containers/buildah/blob/v1.26.1/config.go#L366-L377
# hadolint ignore=DL4006
RUN curl --proto '=https' --tlsv1.2 -sSf "https://raw.githubusercontent.com/rust-lang/rustup/${RUSTUP_VERSION}/rustup-init.sh" \
    | sh -s -- --default-toolchain none -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup show

ARG TARGETARCH=amd64
ENV ARCH="${TARGETARCH}"
ENV GOOS=linux
ENV GOARCH="${TARGETARCH}"

COPY go.mod go.sum /parca-agent/
RUN go mod download -modcacherw

COPY Makefile /parca-agent
COPY bpf /parca-agent/bpf
RUN make -C bpf setup
# hadolint ignore=DL3059
RUN make bpf

COPY . /parca-agent
RUN git submodule init && git submodule update
RUN make build

FROM docker.io/debian:bullseye-slim@sha256:313ee16e6d9b3c186d5fb9632bdb8bf16efbda4e0aac4586f139d92af0554099 AS all

COPY --from=build /etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=build /parca-agent/dist/parca-agent /bin/parca-agent

FROM scratch

COPY --chown=0:0 --from=all / /
RUN chown -R nobody:nogroup /tmp

CMD ["/bin/parca-agent"]
