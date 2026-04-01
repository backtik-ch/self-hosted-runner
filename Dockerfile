FROM ubuntu:24.04

ARG RUNNER_VERSION="2.333.1"
ARG DEBIAN_FRONTEND=noninteractive

# System update
RUN apt update -y && apt upgrade -y

# Install core dependencies (ADD sudo + docker!)
RUN apt install -y --no-install-recommends \
    sudo \
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
    docker.io \
    openssh-client

# Create docker user
RUN useradd -m docker

# Give docker user sudo access (NO PASSWORD)
RUN echo "docker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Add user to docker group
RUN usermod -aG docker docker

# Setup runner
RUN cd /home/docker && mkdir actions-runner && cd actions-runner \
    && curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Fix permissions
RUN chown -R docker:docker /home/docker

# Install runner dependencies
RUN /home/docker/actions-runner/bin/installdependencies.sh

# Copy start script
COPY --chmod=+x start.sh /start.sh

# Switch to docker user
USER docker

ENTRYPOINT ["/start.sh"]
