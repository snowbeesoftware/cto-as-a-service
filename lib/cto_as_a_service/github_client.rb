require "json"
require "net/http"
require "uri"

module CtoAsAService
  class GitHubClient
    def initialize(config)
      @config = config
    end

    def token
      `gh auth token 2>&1`.strip.tap do
        raise GitHubError, "gh not installed or not authenticated" if $?.nil? || !$?.success?
      end
    end

    def post_commit_comment(repo_url, commit_hash, body)
      owner, repo = parse_repo_info(repo_url)
      return unless owner && repo

      uri = URI.parse("https://api.github.com/repos/#{owner}/#{repo}/commits/#{commit_hash}/comments")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/vnd.github.v3+json"
      request.body = JSON.generate({
        body: body
      })

      response = http.request(request)

      unless response.code == "201"
        raise GitHubError, "Failed to post comment: #{response.code} - #{response.body}"
      end

      true
    end

    private

    def parse_repo_info(repo_url)
      if match = repo_url.match(%r{github\.com[/:]([^/]+)/([^/.]+)})
        [match[1], match[2]]
      else
        nil
      end
    end
  end

  class GitHubError < StandardError; end
end
