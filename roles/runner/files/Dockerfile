# GitHub Actions runner for this repo, with Ansible. Holds no credentials: secrets, GitHub App signing and SSH
# signing come from the Wyrwood sockets mounted at /run/wyrwood.
FROM ghcr.io/actions/actions-runner:2.338.2

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git jq openssh-client python3-venv socat \
    && rm -rf /var/lib/apt/lists/*

# Mints GitHub App installation tokens, signing the App's JWT with OpenBao Transit.
ARG GH_APP_TOKEN_VERSION=0.4.0
ARG GH_APP_TOKEN_SHA256=0ce003897b2ae254a61503570db4ef16ea3569b65f40a32674685f6b7f31fe48
RUN curl -fsSLo /usr/local/bin/gh-vault-agent-app-token \
        "https://github.com/wyrd-company/gh-vault-agent-app-token/releases/download/${GH_APP_TOKEN_VERSION}/gh-vault-agent-app-token_${GH_APP_TOKEN_VERSION}_linux-amd64" \
    && echo "${GH_APP_TOKEN_SHA256}  /usr/local/bin/gh-vault-agent-app-token" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/gh-vault-agent-app-token

ARG ANSIBLE_CORE_VERSION=2.21.5
RUN python3 -m venv /opt/ansible \
    && /opt/ansible/bin/pip install --no-cache-dir "ansible-core==${ANSIBLE_CORE_VERSION}" hvac
ENV PATH=/opt/ansible/bin:$PATH

# Jobs need no root in the container.
RUN gpasswd -d runner sudo && rm -f /etc/sudoers.d/runner

COPY entrypoint.sh /usr/local/bin/homelab-runner
RUN chmod 0755 /usr/local/bin/homelab-runner

USER runner
ENTRYPOINT ["/usr/local/bin/homelab-runner"]
