FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends samba \
    && rm -rf /var/lib/apt/lists/*
EXPOSE 137/udp 138/udp 139 445
CMD ["smbd", "--foreground", "--debug-stdout", "--no-process-group"]
