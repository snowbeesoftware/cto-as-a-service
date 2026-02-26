require "yaml"

module CtoAsAService
  class Config
    DEFAULT_CONFIG_FILENAME = ".cto-as-a-service.yaml"
    DEFAULT_LAST_COMMIT_FILENAME = ".cto-as-a-service-last-commit"

    attr_reader :llm_endpoint, :llm_model, :github_token_env_var, :rules_files, :repo_root

    def initialize(repo_root)
      @repo_root = repo_root
      load_config
    end

    def self.from_current_dir
      new(Dir.pwd)
    end

    def config_file_path
      File.join(@repo_root, DEFAULT_CONFIG_FILENAME)
    end

    def last_commit_file_path
      File.join(@repo_root, ".git", "cto-as-a-service-last-commit")
    end

    def last_commit
      File.read(last_commit_file_path).strip if File.exist?(last_commit_file_path)
    end

    def last_commit=(commit_hash)
      File.write(last_commit_file_path, commit_hash)
    end

    def rules_content
      rules_files.map do |path|
        full_path = File.join(@repo_root, path)
        if File.exist?(full_path)
          "=== #{path} ===\n#{File.read(full_path)}"
        else
          nil
        end
      end.compact.join("\n\n")
    end

    def github_token
      ENV[github_token_env_var]
    end

    private

    def load_config
      config_path = config_file_path

      unless File.exist?(config_path)
        raise ConfigError, "Config file not found: #{config_path}\nRun 'cto-as-a-service doctor' for setup instructions."
      end

      config = YAML.safe_load(File.read(config_path), permitted_classes: [], permitted_symbols: [])

      @llm_endpoint = config.dig("llm", "endpoint") || "http://localhost:11434/api/generate"
      @llm_model = config.dig("llm", "model") || "llama3.2"
      @github_token_env_var = config.dig("github", "token_env_var") || "GITHUB_TOKEN"
      @rules_files = config["rules_files"] || [".cto-as-a-service-RULES.md"]
    end
  end

  class ConfigError < StandardError; end
end
