FROM alpine:latest

RUN apk add --no-cache \
    bash \
    zip \
    tzdata \
    curl \
    rclone \
    ca-certificates \
    busybox-suid \
    sqlite

# Set timezone (optional)
ENV TZ=America/Indiana/Indianapolis

# Create working dirs
WORKDIR /app

# Copy scripts
COPY backup.sh /app/backup.sh
RUN chmod +x /app/backup.sh

# Add cron job
RUN echo "0 2 * * * /app/backup.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Run cron in foreground
CMD ["crond", "-f", "-l", "8"]