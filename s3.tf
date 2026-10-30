# deploy/terraform/aws/s3.tf

resource "aws_s3_bucket" "traceroot" {
  bucket_prefix = "${var.name}-"
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "traceroot" {
  bucket = aws_s3_bucket.traceroot.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "traceroot" {
  bucket = aws_s3_bucket.traceroot.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "traceroot" {
  bucket                  = aws_s3_bucket.traceroot.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Only the ingest prefixes under events/ expire; nothing else in the bucket does.
# The bucket is versioned, so expiring an object only hides it behind a delete
# marker: the noncurrent-version rules remove the data, and the last rule removes
# the marker once no versions remain. S3 rejects `days` and
# `expired_object_delete_marker` in one expiration block, hence the separate rule.
resource "aws_s3_bucket_lifecycle_configuration" "traceroot" {
  bucket = aws_s3_bucket.traceroot.id

  # Versioning must be enabled before rules that act on noncurrent versions apply.
  depends_on = [aws_s3_bucket_versioning.traceroot]

  rule {
    id     = "expire-ingest-batches"
    status = "Enabled"

    filter {
      prefix = "events/otel/"
    }

    expiration {
      days = var.ingest_batch_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "expire-ingest-failed"
    status = "Enabled"

    filter {
      prefix = "events/failed/"
    }

    expiration {
      days = var.ingest_failed_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {
      prefix = "events/"
    }

    expiration {
      expired_object_delete_marker = true
    }
  }
}
