terraform {
  # Remote state backend (MinIO/S3).
  # Configure via: ops/scripts/tf-backend-init.sh (no secrets in Git).
  backend "s3" {}
}
