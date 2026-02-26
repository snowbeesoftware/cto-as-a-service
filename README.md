# CTO-as-a-Service

A local commit analyzer that reviews every commit using a local LLM and posts feedback as GitHub comments.

## Overview

CTO-as-a-service sits between your git workflow and GitHub, reviewing each commit against rules you define and leaving constructive feedback directly on the commit in GitHub.

## Requirements

- Ruby 2.6+
- [Ollama](https://ollama.com) running locally with a model installed
- GitHub personal access token (for posting comments)

## Installation

```bash
# Add to your PATH
export PATH="$PATH:~/code/snowbee/cto-as-a-service/bin"

# Verify it works
cto-as-a-service version
```

## Setup

### 1. Install Ollama and a model

```bash
# Install Ollama, then:
ollama list                    # See available models
ollama pull llama3.2          # or your preferred model
```

### 2. Create a GitHub token

Create a personal access token at: https://github.com/settings/tokens

Required scope: `repo` (for public repos, `public_repo` is sufficient)

```bash
export GITHUB_TOKEN="your-token-here"
```

### 3. Configure your repo

Copy the example config and create your rules file:

```bash
cd your-repo
cp ~/code/snowbee/cto-as-a-service/.cto-as-a-service.yaml ./.cto-as-a-service.yaml
cp ~/code/snowbee/cto-as-a-service/COMMIT_RULES.md.example ./.cto-as-a-service-RULES.md
```

Edit `.cto-as-a-service.yaml` to point to your rules files and set the correct model name.

### 4. Install git hooks

```bash
cto-as-a-service install
```

This installs a `post-checkout` hook that runs on every `git checkout`, `git switch`, and `git pull --rebase`.

### 5. Verify setup

```bash
cto-as-a-service doctor
```

## Usage

### Commands

```bash
cto-as-a-service analyze   # Run analysis on current repo (called by hook)
cto-as-a-service install  # Install git hooks to current repo
cto-as-a-service doctor   # Verify setup
cto-as-a-service version  # Show version
cto-as-a-service help     # Show help
```

### First Run

On first run, the tool stores the current HEAD commit in `.git/cto-as-a-service-last-commit` and exits without analyzing any commits. The next time new commits are pulled, those will be analyzed.

To manually set the baseline commit:

```bash
echo "abc123" > .git/cto-as-a-service-last-commit
```

### Workflow

1. Pull new commits (`git pull --rebase` or via IDE)
2. The `post-checkout` hook triggers automatically
3. Tool finds new commits since last run
4. Each commit is analyzed by the LLM against your rules
5. If issues found, a comment is posted to GitHub

## Configuration

See `.cto-as-a-service.yaml` for all options.

```yaml
llm:
  endpoint: "http://localhost:11434/api/generate"
  model: "llama3.2"

github:
  token_env_var: "GITHUB_TOKEN"

rules_files:
  - ".cto-as-a-service-RULES.md"
  - ".docs/guidelines.md"
```

## Rules Files

The tool reads exactly the files you specify in `rules_files`. Nothing is auto-discovered. Each file's content is concatenated and passed to the LLM as context.

## State File

The tool stores its state in `.git/cto-as-a-service-last-commit`. This file is in the `.git` directory so it doesn't show up in `git status`.

## Global Installation (All Repos)

To have the hook automatically in all new repos:

```bash
mkdir -p ~/.git-template/hooks
cp hooks/post-checkout ~/.git-template/hooks/
git init --template ~/.git-template  # In new repos
```

For existing repos, run `cto-as-a-service install` in each repo.

## Changing the LLM

Edit the `model` in your `.cto-as-a-service.yaml`. Available models:

```bash
ollama list
ollama pull <model-name>
```

## Troubleshooting

Run `cto-as-a-service doctor` to check:
- Ruby version
- Config file validity
- GitHub token
- Ollama connectivity
- Model availability
