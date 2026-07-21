#!/bin/bash
set -euo pipefail

DATE=${1:-$(date +%F)}
BUCKET="gs://gke-prod-demo-001-sql-backups"

echo "======================================="
echo "Starting Restore"
echo "======================================="

echo "Downloading SQL Backup..."

gcloud storage cp \
"${BUCKET}/wordpress-${DATE}.sql" .

echo "Importing Cloud SQL..."

gcloud sql import sql \
wordpress-db \
wordpress-${DATE}.sql \
--database=wordpress

echo "Downloading Uploads..."

gcloud storage cp \
"${BUCKET}/uploads-${DATE}.tar.gz" .

echo "Restoring uploads..."

rm -rf /var/www/html/wp-content/uploads/*

tar -xzf uploads-${DATE}.tar.gz \
-C /var/www/html/wp-content

echo "Cleanup..."

rm -f wordpress-${DATE}.sql
rm -f uploads-${DATE}.tar.gz

echo "======================================="
echo "Restore Completed Successfully"
echo "======================================="
