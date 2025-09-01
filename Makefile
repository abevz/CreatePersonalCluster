# CPC Project Makefile
# Provides convenient commands for development, testing, and maintenance

.PHONY: help test test-unit test-integration lint lint-shell lint-ansible clean setup dev-setup

# Default target
help:
	@echo "CPC Project Makefile"
	@echo "==================="
	@echo ""
	@echo "Available targets:"
	@echo "  test           - Run all tests"
	@echo "  test-unit      - Run unit tests only"
	@echo "  test-integration - Run integration tests only"
	@echo "  lint           - Run all linting tools"
	@echo "  lint-shell     - Run shell script linting"
	@echo "  lint-ansible   - Run Ansible linting"
	@echo "  clean          - Clean up temporary files"
	@echo "  setup          - Initial project setup"
	@echo "  dev-setup      - Development environment setup"
	@echo "  help           - Show this help message"

# Testing targets
test:
	@echo "Running all tests..."
	./run_tests.sh

test-unit:
	@echo "Running unit tests..."
	python -m pytest tests/unit/ -v --tb=short

test-integration:
	@echo "Running integration tests..."
	python -m pytest tests/integration/ -v --tb=short

# Linting targets
lint: lint-shell lint-ansible

lint-shell:
	@echo "Running shell linting..."
	shellcheck cpc modules/*.sh
	bashate cpc modules/*.sh

lint-ansible:
	@echo "Running Ansible linting..."
	ansible-lint ansible/playbooks/

# Cleanup
clean:
	@echo "Cleaning up..."
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} +
	find . -name "*.log" -delete
	find . -name ".coverage" -delete
	find . -name "htmlcov" -type d -exec rm -rf {} +
	rm -rf .pytest_cache/

# Setup targets
setup: dev-setup
	@echo "Project setup complete!"

dev-setup:
	@echo "Setting up development environment..."
	# Create virtual environment if it doesn't exist
	@if [ ! -d ".testenv" ]; then \
		echo "Creating virtual environment..."; \
		python -m venv .testenv; \
	fi
	@echo "Activating virtual environment and installing dependencies..."
	@source .testenv/bin/activate && \
	pip install pytest pytest-mock pytest-cov bashate shellcheck-py ansible-lint
	@echo "Development environment ready!"

# Development helpers
test-watch:
	@echo "Running tests in watch mode..."
	python -m pytest tests/ -v --tb=short -f

coverage:
	@echo "Running tests with coverage..."
	python -m pytest tests/ --cov=. --cov-report=html
	@echo "Coverage report generated in htmlcov/"

# Git helpers
status:
	@echo "Git status:"
	@git status --short

commit:
	@echo "Current changes:"
	@git status --porcelain
	@echo ""
	@read -p "Enter commit message: " msg; \
	git add . && \
	git commit -m "$$msg"

push:
	@echo "Pushing to remote..."
	git push origin feature/improvements
