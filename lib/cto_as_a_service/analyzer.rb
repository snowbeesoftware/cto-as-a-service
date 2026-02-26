require "json"
require "net/http"
require "uri"

module CtoAsAService
  class Analyzer
    class AnalysisResult
      attr_reader :has_issues, :issues, :raw_response

      def initialize(has_issues:, issues:, raw_response:)
        @has_issues = has_issues
        @issues = issues
        @raw_response = raw_response
      end
    end

    def initialize(config)
      @config = config
    end

    def analyze_commit(commit_hash, commit_message, diff)
      prompt = build_prompt(commit_hash, commit_message, diff)
      response = call_llm(prompt)
      parse_response(response)
    end

    private

    def build_prompt(commit_hash, commit_message, diff)
      <<~PROMPT
        You are a senior software engineer reviewing commits. Analyze the following commit for issues.

        ## Commit Message
        #{commit_message}

        ## Diff
        #{diff}

        ## Rules to Follow
        #{@config.rules_content}

        ## Output Format
        Respond with a JSON object:
        {
          "has_issues": true/false,
          "issues": ["issue 1", "issue 2"] // only if has_issues is true
        }

        Be strict. If there are ANY issues with the commit (not following rules, bad practices, etc.), set has_issues to true and list the issues.
      PROMPT
    end

    def call_llm(prompt)
      uri = URI.parse(@config.llm_endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({
        model: @config.llm_model,
        prompt: prompt,
        stream: false,
        format: "json"
      })

      response = http.request(request)
      
      unless response.code == "200"
        raise LLMError, "LLM request failed: #{response.code} - #{response.body}"
      end

      response.body
    end

    def parse_response(response_text)
      # Extract JSON from response (might have some text before/after)
      json_match = response_text.match(/\{.*\}/m)
      
      if json_match
        data = JSON.parse(json_match[0])
        AnalysisResult.new(
          has_issues: data["has_issues"] == true,
          issues: data["issues"] || [],
          raw_response: response_text
        )
      else
        # Fallback: if no JSON, assume no issues
        AnalysisResult.new(
          has_issues: false,
          issues: [],
          raw_response: response_text
        )
      end
    rescue JSON::ParserError => e
      raise LLMError, "Failed to parse LLM response: #{e.message}"
    end
  end

  class LLMError < StandardError; end
end
