require "aws-sdk-s3"
require "aws-sdk-sns"
require "net/https"
require_relative "./util"

DRYRUN        = ENV["DRYRUN"]
S3            = Aws::S3::Client.new
SNS           = Aws::SNS::Client.new
S3_BUCKET     = ENV["S3_BUCKET"]     || "brutalismbot"
S3_PREFIX     = ENV["S3_PREFIX"]     || "oauth/v1/"
SNS_TOPIC_ARN = ENV["SNS_TOPIC_ARN"] || "arn:aws:sns:us-east-1:556954866954:slack_brutalismbot_mirror"
USER_AGENT    = "brutalismbot 0.1"

class Post < Hash
  def content_type(user_agent:)
    url = self.dig "data", "url"
    res = request_url url: url, user_agent: user_agent, method: Net::HTTP::Head
    res.header.content_type
  end

  def to_slack
    url       = self.dig "data", "url"
    title     = self.dig "data", "title"
    permalink = self.dig "data", "permalink"
    {
      blocks: [
        {
          type: "image",
          title: {
            type: "plain_text",
            text: "/r/brutalism",
            emoji: true,
          },
          image_url: url,
          alt_text: title,
        },
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: "<https://reddit.com#{permalink}|#{title}>",
            },
          ],
        },
      ],
    }
  end
end

def get_post(s3:, bucket:, key:)
  obj  = s3.get_object bucket: bucket, key: key
  post = JSON.parse obj[:body].read
  Post[post]
end

def publish(sns:, topic_arn:, **params)
  message = JSON.unparse(params)
  publish = {topic_arn: topic_arn, message: message}
  if DRYRUN
    puts "PUBLISH DRYRUN #{JSON.unparse(publish)}"
    params
  else
    puts "PUBLISH #{JSON.unparse(publish)}"
    sns.publish **publish
  end
end

def handler(event:, context:)
  # Log event
  puts "EVENT #{JSON.unparse event}"

  # Interate over S3 put event records
  event["Records"].map do |record|

    # Get post body / content-type
    bucket       = URI.unescape record.dig("s3", "bucket", "name")
    key          = URI.unescape record.dig("s3", "object", "key")
    post         = get_post s3: S3, bucket: bucket, key: key
    content_type = post.content_type user_agent: USER_AGENT

    # Only pubish if content-type is `image/*`
    if content_type =~ /\Aimage\//

      # Publish SNS message for each OAuth
      s3_keys(s3:S3, bucket: S3_BUCKET, prefix: S3_PREFIX).map(&:key).map do |key|
        publish sns:       SNS,
                topic_arn: SNS_TOPIC_ARN,
                bucket:    S3_BUCKET,
                key:       key,
                body:      post.to_slack
      end

    # Otherwise raise TypeError
    else
      error = "s3://#{bucket}/#{key}[#{content_type}]"
      puts "ERROR #{error}"
      raise TypeError.new error
    end
  end.flatten
end
