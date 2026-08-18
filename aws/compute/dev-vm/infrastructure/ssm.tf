# Session auditing.
#
# Session Manager replaces SSH, so this is what replaces the SSH audit trail.
# CloudTrail records that a session was started, by whom, and against which
# instance -- but not a single keystroke of what happened inside it. The
# aws_ssm_document below is what turns on the transcript: with it, every command
# and its output is streamed to CloudWatch Logs (and optionally archived to S3),
# which is the difference between "someone logged in" and an auditable session.
#
# One sharp edge worth knowing: Session Manager only picks up preferences
# automatically from a document literally named SSM-SessionManagerRunShell, which
# is account-wide. This document is named for the stack instead, so it applies
# only when it is passed explicitly:
#
#   aws ssm start-session --target <id> --document-name <this document>
#
# That is exactly what the ssm_start_session_command output emits. Start a session
# without it and you get an unlogged shell.

resource "aws_cloudwatch_log_group" "sessions" {
  name              = "/aws/ssm/${local.name}/sessions"
  retention_in_days = var.session_log_retention_days
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = "${local.name}-sessions"
  })
}

# Separate group for the box's own logs (cloud-init, the seed and idle-shutdown
# units) so a retention change on session transcripts does not silently discard
# the boot evidence you need when the box fails to come up.
resource "aws_cloudwatch_log_group" "dev_vm" {
  name              = "/aws/ec2/${local.name}"
  retention_in_days = var.session_log_retention_days
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = "${local.name}-instance-logs"
  })
}

resource "aws_ssm_document" "session_prefs" {
  name            = "${local.name}-session"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session preferences for ${local.name}: logged, run as ${var.target_user}, bounded duration."
    sessionType   = "Standard_Stream"

    inputs = {
      cloudWatchLogGroupName = aws_cloudwatch_log_group.sessions.name

      # Streaming sends output continuously rather than on session close, so a
      # session that is killed mid-way still leaves a transcript.
      cloudWatchStreamingEnabled = true

      # Only assertable when the log group is actually KMS-encrypted; claiming it
      # otherwise makes Session Manager refuse to start the session.
      cloudWatchEncryptionEnabled = var.kms_key_arn != ""

      s3BucketName        = var.enable_session_log_bucket ? aws_s3_bucket.sessions[0].id : ""
      s3KeyPrefix         = var.enable_session_log_bucket ? "sessions/" : ""
      s3EncryptionEnabled = var.enable_session_log_bucket

      # A forgotten session is a running VM. Both bounds are service-enforced.
      idleSessionTimeout = tostring(var.session_idle_timeout_minutes)
      maxSessionDuration = tostring(var.session_max_duration_minutes)

      # Without runAs, sessions land as ssm-user, whose home has none of the
      # dotfiles the image installed and is not the volume that persists.
      runAsEnabled     = true
      runAsDefaultUser = var.target_user

      # The image sets zsh as the login shell, but Session Manager starts its own
      # shell and ignores /etc/passwd. Fall through to the default shell rather
      # than fail the session if zsh is somehow missing -- a broken shellProfile
      # here is a lockout, and there is no SSH to fall back to.
      shellProfile = {
        linux = "cd ~ && exec $(command -v zsh || command -v bash) -l"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name}-session"
  })
}

# ---------------------------------------------------------------------------
# Optional S3 archive for transcripts
# ---------------------------------------------------------------------------

# CloudWatch answers "what happened in that session" for as long as the log group
# retains it. This exists for keeping transcripts longer than that, cheaply.
resource "aws_s3_bucket" "sessions" {
  count = var.enable_session_log_bucket ? 1 : 0

  bucket = "${local.name}-sessions-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${local.name}-sessions"
  })
}

resource "aws_s3_bucket_public_access_block" "sessions" {
  count = var.enable_session_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.sessions[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sessions" {
  count = var.enable_session_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.sessions[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }

    # Cuts KMS request cost on the many small objects a transcript produces.
    bucket_key_enabled = var.kms_key_arn != ""
  }
}

# Transcripts are append-only evidence; versioning means an overwrite cannot erase
# one.
resource "aws_s3_bucket_versioning" "sessions" {
  count = var.enable_session_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.sessions[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sessions" {
  count = var.enable_session_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.sessions[0].id

  rule {
    id     = "expire-old-transcripts"
    status = "Enabled"

    filter {}

    # A year of transcripts for a personal lab box is pennies; keeping them
    # forever is how a lab bucket becomes a compliance question nobody owns.
    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
