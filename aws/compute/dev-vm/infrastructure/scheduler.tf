# Scheduled hard stop.
#
# The second half of the auto-stop design. shared/bootstrap/idle-shutdown.sh
# reacts to actual idleness from inside the box, which is the better signal but
# useless if the box wedges. This is the backstop that runs whether or not the
# guest is healthy.
#
# EventBridge Scheduler's universal target calls the EC2 StopInstances API
# directly, so there is no Lambda to write, package, patch or pay for -- the whole
# mechanism is this resource plus the IAM role in iam.tf.

resource "aws_scheduler_schedule" "auto_stop" {
  name        = "${local.name}-auto-stop"
  description = "Hard stop for ${local.name}; backstop for the on-box idle timer."

  state = var.auto_stop_enabled ? "ENABLED" : "DISABLED"

  # OFF means "run at exactly this time". A flexible window would let AWS spread
  # invocations, which is pointless for a single instance and makes "why is it
  # still up?" harder to answer.
  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.auto_stop_cron
  schedule_expression_timezone = var.auto_stop_timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler.arn

    # Universal targets take the SDK request shape, so this is the StopInstances
    # payload verbatim -- PascalCase keys included.
    input = jsonencode({
      InstanceIds = [aws_instance.dev_vm.id]
    })

    # Stopping an already-stopped instance is a no-op success, so retries are only
    # ever paying for a transient API failure.
    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 300
    }
  }
}
