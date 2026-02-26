$LOAD_PATH.unshift File.expand_path("../../", __FILE__)
require "cto_as_a_service/version"
require "cto_as_a_service/config"
require "cto_as_a_service/git_utils"
require "cto_as_a_service/analyzer"
require "cto_as_a_service/github_client"

module CtoAsAService
  class CLI
    COLORS = {
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      cyan: "\e[36m",
      reset: "\e[0m"
    }

    def self.color(text, color_name)
      "#{COLORS[color_name]}#{text}#{COLORS[:reset]}"
    end

    def self.run(args)
      command = args.shift || "help"

      case command
      when "analyze"
        analyze
      when "install"
        install
      when "doctor"
        doctor
      when "version", "--version", "-v"
        puts "cto-as-a-service v#{VERSION}"
      when "help", "-h", "--help", nil
        puts <<~HELP
          CTO-as-a-service - Local commit analyzer powered by LLM

          Usage:
            cto-as-a-service <command>

          Commands:
            analyze   Analyze new commits since last run (hook calls this)
            install   Install git hooks to current repo
            doctor    Verify setup is correct
            version   Show version
            help      Show this message

          Quick Start:
            1. Install Ollama + gh CLI
            2. gh auth login
            3. cd your-repo
            4. cto-as-a-service install
        HELP
      else
        puts "Unknown command: #{command}"
        puts "Run 'cto-as-a-service help' for usage"
        exit 1
      end
    end

    def self.analyze
      puts color("Analyzing commits...", :yellow)

      config = Config.from_current_dir

      current_commit = GitUtils.current_commit(config.repo_root)
      last_commit = config.last_commit

      if last_commit == current_commit
        puts color("No new commits to analyze.", :green)
        return
      end

      commits = if last_commit.nil? || last_commit.empty?
        # First run: store current HEAD and exit without analyzing
        puts color("First run - storing current HEAD and exiting.", :yellow)
        config.last_commit = current_commit
        puts color("Done! Next run will analyze new commits.", :green)
        return
      else
        GitUtils.commits_between(config.repo_root, last_commit, current_commit)
      end

      if commits.empty?
        puts color("No new commits to analyze.", :green)
        return
      end

      puts color("Found #{commits.count} new commit(s).", :yellow)

      analyzer = Analyzer.new(config)
      github = GitHubClient.new(config)
      repo_url = GitUtils.remote_info(config.repo_root)

      commits.each do |commit_hash|
        puts color("\nAnalyzing commit #{commit_hash[0..7]}...", :yellow)
        
        commit_message = GitUtils.commit_message(config.repo_root, commit_hash)
        diff = GitUtils.commit_diff(config.repo_root, commit_hash)

        begin
          result = analyzer.analyze_commit(commit_hash, commit_message, diff)

          if result.has_issues
            puts color("Issues found!", :red)
            
            comment_body = <<~COMMENT
              ## CTO-as-a-Service Review

              **Issues found:**

              #{result.issues.map { |i| "- #{i}" }.join("\n")}

              ---
              *This comment was automatically posted by CTO-as-a-Service*
            COMMENT

            if repo_url && config.github_token
              puts color("Posting comment to GitHub...", :yellow)
              github.post_commit_comment(repo_url, commit_hash, comment_body)
              puts color("Comment posted!", :green)
            else
              puts color("GitHub token or repo URL not available. Skipping comment.", :yellow)
              puts color("Would have posted:", :yellow)
              puts comment_body
            end
          else
            puts color("No issues found.", :green)
          end
        rescue => e
          puts color("Error analyzing commit: #{e.message}", :red)
        end
      end

      config.last_commit = current_commit
      puts color("\nDone!", :green)
    end

    def self.install
      repo_root = Dir.pwd
      hook_dir = File.join(repo_root, ".git", "hooks")
      hook_path = File.join(hook_dir, "post-checkout")

      unless File.directory?(hook_dir)
        puts color("Error: Not a git repository", :red)
        exit 1
      end

      config_path = File.join(repo_root, Config::DEFAULT_CONFIG_FILENAME)
      
      # Create config file if it doesn't exist
      unless File.exist?(config_path)
        puts color("No config file found. Creating default config...", :yellow)
        
        default_config = <<~CONFIG
          llm:
            endpoint: "http://localhost:11434/api/generate"
            model: "llama3.2"

          rules_files:
            - ".cto-as-a-service-RULES.md"
        CONFIG
        
        File.write(config_path, default_config)
        puts color("Created #{config_path}", :green)
        
        # Create example rules file too
        rules_path = File.join(repo_root, ".cto-as-a-service-RULES.md")
        unless File.exist?(rules_path)
          example_rules = <<~RULES
            # CTO-as-a-Service Commit Rules

            ## General Guidelines

            - Commits should be focused and atomic
            - Commit messages should be clear and descriptive
            - Follow the project's coding standards

            ## Commit Message Rules

            1. **Subject line** should be:
               - Max 50 characters
               - Start with a verb in imperative mood (e.g., "Add", "Fix", "Update")
               - No period at the end

            2. **Body** (if present) should:
               - Wrap at 72 characters
               - Explain "what" and "why", not "how"
               - Reference issue numbers if applicable

            ## Code Quality Rules

            1. **No TODO comments left behind** - All TODO/FIXME comments must have an associated issue number
            2. **No debug code** - Remove console.log, print statements, etc.
            3. **No secrets** - Never commit API keys, tokens, or credentials
            4. **Tests** - Include tests for new functionality
          RULES
          File.write(rules_path, example_rules)
          puts color("Created #{rules_path}", :green)
        end
        
        puts
      end

      bin_path = File.expand_path("../../../bin/cto-as-a-service", __FILE__)

      hook_content = <<~HOOK
        #!/bin/bash

        # CTO-as-a-service post-checkout hook
        # Generated by cto-as-a-service

        # Only run on branch checkouts (not file checkouts)
        if [ "$3" = "1" ]; then
          #{bin_path} analyze
        fi
      HOOK

      if File.exist?(hook_path)
        existing_content = File.read(hook_path)
        if existing_content.include?("cto-as-a-service")
          puts color("Hook already installed.", :yellow)
        else
          puts color("Existing post-checkout hook found. Please manually add the call to cto-as-a-service.", :red)
          puts color("Add this to your post-checkout hook:", :yellow)
          puts bin_path
        end
      else
        File.write(hook_path, hook_content)
        File.chmod(0o755, hook_path)
        puts color("Installed post-checkout hook to #{hook_path}", :green)
      end

      puts color("\nRunning doctor to verify setup...", :cyan)
      puts
      doctor
    end

    def self.doctor
      puts color("Running diagnostics...", :yellow)
      puts

      all_ok = true

      puts "Ruby: #{RUBY_VERSION}"

      config_path = File.join(Dir.pwd, Config::DEFAULT_CONFIG_FILENAME)
      if File.exist?(config_path)
        puts color("Config file: Found", :green)
        
        begin
          config = Config.from_current_dir
          puts "  LLM endpoint: #{config.llm_endpoint}"
          puts "  LLM model: #{config.llm_model}"
          puts "  GitHub token env var: #{config.github_token_env_var}"
          puts "  Rules files: #{config.rules_files.join(', ')}"
        rescue => e
          puts color("  Config error: #{e.message}", :red)
          all_ok = false
        end
      else
        puts color("Config file: Not found (#{config_path})", :red)
        all_ok = false
      end
      puts

      puts "Checking GitHub CLI (gh)..."
      begin
        gh_version = `gh --version 2>&1`.strip.split("\n").first
        if $?.success?
          puts color("GitHub CLI: Installed (#{gh_version})", :green)
          
          token = `gh auth token 2>&1`.strip
          if $?.success? && !token.empty?
            puts color("  Authenticated", :green)
          else
            puts color("  Not authenticated. Run: gh auth login", :red)
            all_ok = false
          end
        else
          puts color("GitHub CLI: Not found (brew install gh)", :red)
          all_ok = false
        end
      rescue => e
        puts color("GitHub CLI: Error - #{e.message}", :red)
        all_ok = false
      end
      puts

      puts "Checking Ollama..."
      begin
        uri = URI.parse("http://localhost:11434/api/tags")
        http = Net::HTTP.new(uri.host, uri.port)
        response = http.get(uri.path)
        
        if response.code == "200"
          models = JSON.parse(response.body)["models"] || []
          puts color("Ollama: Running", :green)
          
          if config
            model_exists = models.any? { |m| m["name"] == config.llm_model }
            if model_exists
              puts color("  Model '#{config.llm_model}': Installed", :green)
            else
              puts color("  Model '#{config.llm_model}': NOT installed", :red)
              puts color("  Available models: #{models.map { |m| m['name'] }.join(', ')}", :yellow)
              all_ok = false
            end
          end
        else
          puts color("Ollama: Not responding (#{response.code})", :red)
          all_ok = false
        end
      rescue => e
        puts color("Ollama: Not reachable (#{e.message})", :red)
        all_ok = false
      end
      puts

      puts "Checking git remote..."
      begin
        repo_url = GitUtils.remote_info(Dir.pwd)
        if repo_url
          puts color("Remote: #{repo_url}", :green)
        else
          puts color("Remote: Not found or not a GitHub repo", :yellow)
        end
      rescue => e
        puts color("Remote: Error - #{e.message}", :yellow)
      end
      puts

      if all_ok
        puts color("All checks passed!", :green)
      else
        puts color("Some checks failed. Please fix the issues above.", :red)
        exit 1
      end
    end
  end
end

CtoAsAService::CLI.run(ARGV)
