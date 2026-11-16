FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends zsh git ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
CMD ["zsh", "-lc", "zsh --version && git --version && echo orca-ok"]
