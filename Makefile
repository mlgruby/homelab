# HomeLab Project Linting and Validation

.PHONY: help lint lint-shell lint-python lint-markdown lint-json lint-nix clean fix-markdown deploy deploy-dry deploy-cleanup cleanup-k3s workflow quick-workflow pre-commit

# Default target
help:
	@echo "🧹 HomeLab Linting Commands"
	@echo "=========================="
	@echo ""
	@echo "Main Commands:"
	@echo "  make lint          - Run all linting checks"
	@echo "  make lint-quick    - Run quick syntax checks only"
	@echo "  make deploy        - Deploy cluster (with confirmation)"
	@echo "  make deploy-dry    - Preview deployment (dry-run)"
	@echo ""
	@echo "Individual Linters:"
	@echo "  make lint-shell    - Check shell scripts with shellcheck"
	@echo "  make lint-python   - Check Python scripts for syntax/style"
	@echo "  make lint-markdown - Check markdown files with markdownlint"
	@echo "  make lint-json     - Validate JSON configuration files"
	@echo "  make lint-nix      - Validate Nix configurations"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-cleanup - Deploy with k3s node cleanup"
	@echo "  make cleanup-k3s    - Clean up removed k3s nodes only"
	@echo ""
	@echo "Workflows:"
	@echo "  make workflow       - Complete workflow (clean + lint + deploy-dry)"
	@echo "  make quick-workflow - Quick workflow (clean + validate + lint-quick)"
	@echo "  make pre-commit     - Pre-commit checks (clean + lint + test)"
	@echo ""
	@echo "Utilities:"
	@echo "  make fix-markdown   - Auto-fix markdown formatting issues"
	@echo "  make clean          - Clean up temporary files"

# Run all linting checks
lint: lint-shell lint-python lint-json lint-nix lint-markdown
	@echo ""
	@echo "🎉 All linting checks completed!"

# Quick syntax checks only (no style/formatting)
lint-quick: lint-shell lint-python lint-json
	@echo ""
	@echo "✅ Quick syntax checks completed!"

# Shell script linting
lint-shell:
	@echo "🐚 Checking shell scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck scripts/*.sh && echo "  ✅ Shell scripts passed"; \
	else \
		echo "  ⚠️  shellcheck not found, skipping shell linting"; \
	fi

# Python script linting
lint-python:
	@echo "🐍 Checking Python scripts..."
	@python3 -m py_compile scripts/*.py && echo "  ✅ Python syntax check passed"
	@python3 -c "import ast, sys; files = ['scripts/generate-configs.py', 'scripts/cleanup-nodes.py']; [ast.parse(open(f).read()) for f in files]; print('  ✅ All Python files have valid syntax')"

# JSON validation
lint-json:
	@echo "📋 Validating JSON files..."
	@python3 -c "import json; json.load(open('cluster.json')); print('  ✅ cluster.json: Valid JSON')"

# Nix configuration validation
lint-nix:
	@echo "❄️  Validating Nix configurations..."
	@echo "  Checking nuc1 config..."
	@nix eval .#nixosConfigurations.nuc1.config.system.build.toplevel.drvPath >/dev/null 2>&1 && echo "    ✅ nuc1: OK"
	@echo "  Checking nuc2 config..."
	@nix eval .#nixosConfigurations.nuc2.config.system.build.toplevel.drvPath >/dev/null 2>&1 && echo "    ✅ nuc2: OK"
	@echo "  Checking nuc3 config..."
	@nix eval .#nixosConfigurations.nuc3.config.system.build.toplevel.drvPath >/dev/null 2>&1 && echo "    ✅ nuc3: OK"
	@echo "  Checking deploy configuration..."
	@nix eval .#deploy.nodes --apply builtins.attrNames >/dev/null 2>&1 && echo "    ✅ deploy: OK"
	@echo "  ✅ All Nix configurations are valid"

# Markdown linting
lint-markdown:
	@echo "📝 Checking markdown files..."
	@if command -v markdownlint >/dev/null 2>&1; then \
		if markdownlint *.md; then \
			echo "  ✅ Markdown files passed"; \
		else \
			echo "  ⚠️  Markdown linting found issues (run 'make fix-markdown' to auto-fix)"; \
		fi \
	else \
		echo "  ⚠️  markdownlint not found, skipping markdown linting"; \
		echo "      Install with: npm install -g markdownlint-cli"; \
	fi

# Auto-fix markdown formatting
fix-markdown:
	@echo "🔧 Auto-fixing markdown formatting..."
	@if command -v markdownlint >/dev/null 2>&1; then \
		markdownlint --fix *.md && echo "  ✅ Markdown files auto-fixed"; \
	else \
		echo "  ❌ markdownlint not found"; \
		echo "      Install with: npm install -g markdownlint-cli"; \
	fi

# Deployment commands
deploy:
	@echo "🚀 Deploying cluster..."
	@./scripts/deploy-cluster.sh

deploy-dry:
	@echo "🔍 Preview deployment (dry-run)..."
	@./scripts/deploy-cluster.sh --dry-run

deploy-cleanup:
	@echo "🧹 Deploying with k3s cleanup..."
	@./scripts/deploy-cluster.sh --cleanup-k3s

cleanup-k3s:
	@echo "🗑️  Cleaning up removed k3s nodes..."
	@python3 scripts/cleanup-nodes.py

# Test deployment script
test-deploy:
	@echo "🚀 Testing deployment workflow..."
	@./scripts/deploy-cluster.sh --dry-run
	@echo "  ✅ Deployment script test completed"

# Validate cluster configuration
validate-cluster:
	@echo "🏠 Validating cluster configuration..."
	@python3 scripts/generate-configs.py
	@echo "  ✅ Cluster configuration is valid"

# Generate and validate all configs
generate-and-validate: validate-cluster lint-nix
	@echo "  ✅ Configuration generation and validation completed"

# Clean up temporary files
clean:
	@echo "🧹 Cleaning up temporary files..."
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*~" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@echo "  ✅ Cleanup completed"

# Complete workflow - validate, lint, and deploy
workflow: clean lint deploy-dry
	@echo ""
	@echo "🎯 Complete workflow validation completed!"
	@echo "   Ready to run 'make deploy' when you're satisfied."

# Quick workflow - generate configs and validate
quick-workflow: clean validate-cluster lint-quick
	@echo ""
	@echo "⚡ Quick workflow completed!"

# Development workflow - run before committing
pre-commit: clean lint test-deploy
	@echo ""
	@echo "🎯 Pre-commit checks completed!"
	@echo "   Ready to commit your changes."
