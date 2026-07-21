#!/bin/bash
set -euo pipefail

DATE=$(date +%F)
BUCKET="gs://gke-prod-demo-001-sql-backups"

echo "======================================="
echo "Starting Backup : ${DATE}"
echo "======================================="

echo "Exporting Cloud SQL database..."

gcloud sql export sql \
  wordpress-db \
  "${BUCKET}/wordpress-${DATE}.sql" \
  --database=wordpress

echo "Cloud SQL export completed."

echo "Creating uploads archive..."

tar -czf "uploads-${DATE}.tar.gz" \
  -C /var/www/html/wp-content uploads

echo "Uploading uploads archive..."

gcloud storage cp \
  "uploads-${DATE}.tar.gz" \
  "${BUCKET}/uploads-${DATE}.tar.gz"

echo "Cleaning local archive..."

rm -f "uploads-${DATE}.tar.gz"

echo "======================================="
echo "Backup completed successfully"
echo "======================================="
