FROM ubuntu:24.04

ARG RUNNER_VERSION="2.335.1"
ARG DEBIAN_FRONTEND=noninteractive

# System update
RUN apt update -y && apt upgrade -y

# Install core dependencies
RUN apt install -y --no-install-recommends \
    curl \
    git \
    unzip \
    jq \
    ca-certificates \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3 \
    python3-venv \
    python3-dev \
    python3-pip \
    openssh-client

# Create runner user
RUN useradd -m runner

# Setup runner
RUN cd /home/runner && mkdir actions-runner && cd actions-runner \
    && curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Fix permissions
RUN chown -R runner:runner /home/runner

# Install runner dependencies
RUN /home/runner/actions-runner/bin/installdependencies.sh

# Copy start script
COPY --chmod=+x start.sh /start.sh
COPY --chmod=+x healthcheck.sh /healthcheck.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD /healthcheck.sh

ENTRYPOINT ["/start.sh"]
