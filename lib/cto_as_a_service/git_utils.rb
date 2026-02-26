module CtoAsAService
  module GitUtils
    class GitError < StandardError; end

    def self.current_commit(repo_root)
      run_git(repo_root, "rev-parse", "HEAD").strip
    end

    def self.commit_message(repo_root, commit_hash)
      run_git(repo_root, "log", "-1", "--format=%B", commit_hash).strip
    end

    def self.commit_diff(repo_root, commit_hash)
      run_git(repo_root, "show", commit_hash, "--format=").strip
    end

    def self.commits_between(repo_root, from_commit, to_commit)
      return [] if from_commit.nil? || from_commit.empty?

      output = run_git(repo_root, "log", "#{from_commit}..#{to_commit}", "--format=%H", "--reverse")
      output.split("\n").map(&:strip).reject(&:empty?)
    end

    def self.commits_since(repo_root, from_commit)
      commits_between(repo_root, from_commit, "HEAD")
    end

    def self.remote_info(repo_root)
      output = run_git(repo_root, "remote", "-v")
      return nil if output.nil? || output.empty?

      if match = output.match(/origin\s+(\S+)\s+\(fetch\)/)
        url = match[1]

        if url =~ /^git@github\.com:(.+)\.git$/
          "https://github.com/#{$1}"
        elsif url =~ /^https?:\/\/github\.com\/(.+)$/
          "https://github.com/#{$1}"
        else
          nil
        end
      else
        nil
      end
    end

    private

    def self.run_git(repo_root, *args)
      Dir.chdir(repo_root) do
        `git #{args.join(" ")} 2>&1`.tap do |output|
          raise GitError, "git error: #{output}" if $?.nil? || !$?.success?
        end
      end
    end
  end
end
