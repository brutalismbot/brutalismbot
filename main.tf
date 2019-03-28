provider archive {
  version = "~> 1.2"
}

provider aws {
  access_key = "${var.aws_access_key_id}"
  profile    = "${var.aws_profile}"
  region     = "${var.aws_region}"
  secret_key = "${var.aws_secret_access_key}"
  version    = "~> 2.3"
}

locals {
  url_new    = "https://www.reddit.com/r/brutalism/new.json?sort=new"
  url_top    = "https://www.reddit.com/r/brutalism/top.json?limit=1"
  user_agent = "brutalismbot 0.1"
  tags {
    App     = "brutalismbot"
    Release = "${var.release}"
    Repo    = "${var.repo}"
  }
}

data archive_file package {
  output_path = "${path.module}/dist/package.zip"
  source_dir  = "${path.module}/lib"
  type        = "zip"
}

data aws_kms_key key {
  key_id = "alias/brutalismbot"
}

data aws_iam_policy_document s3 {
  statement {
    actions   = ["s3:*"]
    resources = [
      "${aws_s3_bucket.brutalismbot.arn}",
      "${aws_s3_bucket.brutalismbot.arn}/*",
    ]
  }
}

resource aws_cloudwatch_dashboard dash {
  dashboard_name = "Brutalismbot"
  dashboard_body = "${file("${path.module}/dashboard.json")}"
}

resource aws_cloudwatch_event_rule posts {
  description         = "Cache posts from /r/brutalism to S3"
  name                = "brutalismbot-cache-posts"
  schedule_expression = "rate(1 hour)"
}

resource aws_cloudwatch_event_target posts {
  rule  = "${aws_cloudwatch_event_rule.posts.name}"
  arn   = "${aws_lambda_function.posts.arn}"
}

resource aws_cloudwatch_log_group oauth {
  name              = "/aws/lambda/${aws_lambda_function.oauth.function_name}"
  retention_in_days = 30
  tags              = "${local.tags}"
}

resource aws_cloudwatch_log_group posts {
  name              = "/aws/lambda/${aws_lambda_function.posts.function_name}"
  retention_in_days = 30
  tags              = "${local.tags}"
}

resource aws_cloudwatch_log_group dispatch {
  name              = "/aws/lambda/${aws_lambda_function.dispatch.function_name}"
  retention_in_days = 30
  tags              = "${local.tags}"
}

resource aws_cloudwatch_log_group mirror {
  name              = "/aws/lambda/${aws_lambda_function.mirror.function_name}"
  retention_in_days = 30
  tags              = "${local.tags}"
}

resource aws_cloudwatch_log_group uninstall {
  name              = "/aws/lambda/${aws_lambda_function.uninstall.function_name}"
  retention_in_days = 30
  tags              = "${local.tags}"
}

/*
resource aws_kms_key brutalismbot {
  description = "Brutalismbot Slack App"
  tags        = "${local.tags}"
}

resource aws_kms_alias brutalismbot {
  name          = "alias/brutalismbot"
  target_key_id = "${aws_kms_key.brutalismbot.key_id}"
}
*/

resource aws_iam_role_policy brutalismbot_s3 {
  name   = "s3"
  policy = "${data.aws_iam_policy_document.s3.json}"
  role   = "${module.slackbot.role_name}"
}

resource aws_lambda_function oauth {
  description      = "Cache OAuth events"
  filename         = "${data.archive_file.package.output_path}"
  function_name    = "brutalismbot-oauth-cache"
  handler          = "oauth.handler"
  role             = "${module.slackbot.role_arn}"
  runtime          = "ruby2.5"
  source_code_hash = "${filebase64sha256("${data.archive_file.package.output_path}")}"
  tags             = "${local.tags}"

  environment {
    variables {
      S3_BUCKET = "${aws_s3_bucket.brutalismbot.bucket}"
      S3_PREFIX = "oauth/v1/"
    }
  }
}

resource aws_lambda_function posts {
  description      = "Cache posts from /r/brutalism"
  filename         = "${data.archive_file.package.output_path}"
  function_name    = "brutalismbot-posts-cache"
  handler          = "posts.handler"
  role             = "${module.slackbot.role_arn}"
  runtime          = "ruby2.5"
  source_code_hash = "${filebase64sha256("${data.archive_file.package.output_path}")}"
  tags             = "${local.tags}"
  timeout          = 15

  environment {
    variables {
      S3_BUCKET  = "${aws_s3_bucket.brutalismbot.bucket}"
      S3_PREFIX  = "posts/v1/"
      URL        = "${local.url_new}"
      USER_AGENT = "${local.user_agent}"
    }
  }
}

resource aws_lambda_function dispatch {
  description      = "Dispatch posts from /r/brutalism"
  filename         = "${data.archive_file.package.output_path}"
  function_name    = "brutalismbot-posts-dispatch"
  handler          = "dispatch.handler"
  role             = "${module.slackbot.role_arn}"
  runtime          = "ruby2.5"
  source_code_hash = "${filebase64sha256("${data.archive_file.package.output_path}")}"
  tags             = "${local.tags}"
  timeout          = 30

  environment {
    variables {
      S3_BUCKET     = "${aws_s3_bucket.brutalismbot.bucket}"
      S3_PREFIX     = "oauth/v1/"
      SNS_TOPIC_ARN = "${aws_sns_topic.mirror.arn}"
      USER_AGENT    = "${local.user_agent}"
    }
  }
}

resource aws_lambda_function mirror {
  description      = "Mirror posts from /r/brutalism to Slack"
  filename         = "${data.archive_file.package.output_path}"
  function_name    = "brutalismbot-posts-mirror"
  handler          = "mirror.handler"
  role             = "${module.slackbot.role_arn}"
  runtime          = "ruby2.5"
  source_code_hash = "${filebase64sha256("${data.archive_file.package.output_path}")}"
  tags             = "${local.tags}"
}

resource aws_lambda_function uninstall {
  description      = "Uninstall brutalismbot from workspace"
  filename         = "${data.archive_file.package.output_path}"
  function_name    = "brutalismbot-uninstall"
  handler          = "uninstall.handler"
  role             = "${module.slackbot.role_arn}"
  runtime          = "ruby2.5"
  source_code_hash = "${filebase64sha256("${data.archive_file.package.output_path}")}"
  tags             = "${local.tags}"
}

resource aws_lambda_permission oauth {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.oauth.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${module.slackbot.oauth_topic_arn}"
}

resource aws_lambda_permission posts {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.posts.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.posts.arn}"
}

resource aws_lambda_permission dispatch {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.dispatch.arn}"
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.brutalismbot.arn}"
}

resource aws_lambda_permission mirror {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.mirror.arn}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${aws_sns_topic.mirror.arn}"
}

resource aws_lambda_permission uninstall {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.uninstall.arn}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${aws_sns_topic.uninstall.arn}"
}

resource aws_s3_bucket brutalismbot {
  acl           = "private"
  bucket        = "brutalismbot"
  force_destroy = false

  /*server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "${data.aws_kms_key.key.arn}"
        sse_algorithm     = "aws:kms"
      }
    }
  }*/
}

resource aws_s3_bucket_notification posts {
  bucket = "${aws_s3_bucket.brutalismbot.id}"

  lambda_function {
    id                  = "dispatch-posts"
    lambda_function_arn = "${aws_lambda_function.dispatch.arn}"
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "posts/v1/"
    filter_suffix       = ".json"
  }
}

resource aws_sns_topic mirror {
  name = "brutalismbot_mirror"
}

resource aws_sns_topic uninstall {
  name = "brutalismbot_event_app_uninstalled"
}

resource aws_sns_topic_subscription oauth {
  endpoint  = "${aws_lambda_function.oauth.arn}"
  protocol  = "lambda"
  topic_arn = "${module.slackbot.oauth_topic_arn}"
}

resource aws_sns_topic_subscription mirror {
  endpoint  = "${aws_lambda_function.mirror.arn}"
  protocol  = "lambda"
  topic_arn = "${aws_sns_topic.mirror.arn}"
}

resource aws_sns_topic_subscription uninstall {
  endpoint  = "${aws_lambda_function.uninstall.arn}"
  protocol  = "lambda"
  topic_arn = "${aws_sns_topic.uninstall.arn}"
}

module slackbot {
  source               = "amancevice/slackbot/aws"
  version              = "13.2.0"
  api_description      = "Brutalismbot REST API"
  api_name             = "brutalismbot"
  api_stage_name       = "v1"
  api_stage_tags       = "${local.tags}"
  base_url             = "/brutalismbot"
  kms_key_id           = "${data.aws_kms_key.key.key_id}"
  lambda_function_name = "brutalismbot-api"
  lambda_tags          = "${local.tags}"
  log_group_tags       = "${local.tags}"
  role_name            = "brutalismbot"
  role_tags            = "${local.tags}"
  secret_name          = "brutalismbot"
  sns_topic_prefix     = "brutalismbot"
}
