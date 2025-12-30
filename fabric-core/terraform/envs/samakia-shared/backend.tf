terraform {
  # Remote state backend (MinIO/S3).
  # Bootstrap note: the MinIO env itself must be applied once with -backend=false,
  # then migrated via: ops/scripts/tf-backend-init.sh samakia-minio --migrate
  backend "s3" {}
}
