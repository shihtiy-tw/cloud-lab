# Instance role for the VM, and the separate role EventBridge Scheduler uses to
# stop it.
#
# Deliberately scoped, and the scoping is the point: this role is what an attacker
# who lands on the box inherits. It can register with SSM, write its own logs, and
# describe things. It cannot create, modify or delete anything, and it cannot
# assume anything.
#
# Admin lives on the human's identity, not on the machine. The workflow is to
# assume an admin role from inside the shell -- `aws sts assume-role`, or the
# dotfiles' own profile switcher -- so the privilege exists only for the length of
# a command in a session that is recorded in CloudTrail against a person. Giving
# the instance profile admin instead would make every process on the box, and
# every dependency it installs, an administrator.

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "dev_vm_assume_role" {
  statement {
    sid     = "AllowEC2ToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dev_vm" {
  name        = "${local.name}-instance"
  description = "dev-vm instance role: SSM registration, own logs, read-only describe. No admin by design."

  assume_role_policy = data.aws_iam_policy_document.dev_vm_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name}-instance"
  })
}

# Session Manager itself. This is the only AWS-managed policy attached, and it is
# what makes the agent able to open the outbound channel that replaces SSH.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.dev_vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "dev_vm" {
  # Writing to its own log group, and nothing else's. Session transcripts and the
  # box's own logs both land here.
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.sessions.arn,
      "${aws_cloudwatch_log_group.sessions.arn}:*",
      "${aws_cloudwatch_log_group.dev_vm.arn}:*",
    ]
  }

  # logs:DescribeLogGroups has no resource-level support; the agent calls it to
  # confirm the configured group exists before streaming to it.
  statement {
    sid       = "DescribeLogGroups"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # Read-only orientation: which instance am I, which volumes are attached, what
  # is my own tag set. The EC2 Describe* actions do not support resource-level
  # permissions at all, so "*" here is the API's constraint rather than a shortcut.
  statement {
    sid    = "ReadOnlyDescribe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }

  # Self-identification, so `aws sts get-caller-identity` works and the human can
  # see which identity they are before assuming a real one.
  statement {
    sid       = "IdentifySelf"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # Only present when session transcripts are archived to S3. Scoped to the
  # bucket this stack created; the instance can add objects and cannot list,
  # delete or read them back.
  dynamic "statement" {
    for_each = var.enable_session_log_bucket ? [1] : []

    content {
      sid       = "WriteSessionTranscripts"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.sessions[0].arn}/*"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_session_log_bucket ? [1] : []

    content {
      sid       = "DiscoverSessionBucketEncryption"
      effect    = "Allow"
      actions   = ["s3:GetEncryptionConfiguration"]
      resources = [aws_s3_bucket.sessions[0].arn]
    }
  }

  # A customer-managed key is only usable if the principal is allowed to use it.
  # Encrypt-side grants only: the instance can write encrypted logs, and can read
  # its own encrypted volumes because EBS decryption happens outside the guest.
  dynamic "statement" {
    for_each = var.kms_key_arn != "" ? [1] : []

    content {
      sid    = "UseCustomerManagedKey"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "dev_vm" {
  name   = "${local.name}-instance"
  role   = aws_iam_role.dev_vm.id
  policy = data.aws_iam_policy_document.dev_vm.json
}

resource "aws_iam_instance_profile" "dev_vm" {
  name = "${local.name}-instance"
  role = aws_iam_role.dev_vm.name

  tags = merge(local.common_tags, {
    Name = "${local.name}-instance"
  })
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    sid     = "AllowSchedulerToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    # Confused-deputy guard: without these the role could be used by any
    # schedule in any account that guesses its ARN.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/*/${local.name}-auto-stop"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name        = "${local.name}-scheduler"
  description = "Lets EventBridge Scheduler stop the dev-vm, and nothing else."

  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name}-scheduler"
  })
}

data "aws_iam_policy_document" "scheduler" {
  # One action, one instance. ec2:StopInstances does support resource-level
  # permissions, so there is no excuse for a wildcard here.
  statement {
    sid       = "StopThisInstanceOnly"
    effect    = "Allow"
    actions   = ["ec2:StopInstances"]
    resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.dev_vm.id}"]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.name}-scheduler"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}
