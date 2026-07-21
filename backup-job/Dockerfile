FROM google/cloud-sdk:slim

RUN apt-get update && \
    apt-get install -y tar gzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /scripts

COPY backup.sh .
COPY restore.sh .
COPY entrypoint.sh .

RUN chmod +x \
    /scripts/backup.sh \
    /scripts/restore.sh \
    /scripts/entrypoint.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
