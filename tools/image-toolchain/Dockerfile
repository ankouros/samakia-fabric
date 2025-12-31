FROM debian:12-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

COPY versions.env /opt/versions.env

RUN set -eux; \
    . /opt/versions.env; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip \
      python3 \
      python3-pip \
      "qemu-utils=${QEMU_UTILS_VERSION}" \
      "libguestfs-tools=${LIBGUESTFS_TOOLS_VERSION}" \
      gnupg; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL -o /tmp/packer.zip "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"; \
    unzip /tmp/packer.zip -d /usr/local/bin; \
    rm -f /tmp/packer.zip; \
    python3 -m pip install --no-cache-dir "ansible==${ANSIBLE_VERSION}"; \
    curl -fsSL -o /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64"; \
    chmod +x /usr/local/bin/jq; \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64"; \
    chmod +x /usr/local/bin/yq; \
    groupadd -r toolchain; \
    useradd -r -g toolchain -m -u 10001 toolchain

USER toolchain
WORKDIR /workspace
