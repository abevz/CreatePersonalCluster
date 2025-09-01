#!/bin/bash
# Test runner script for CPC project

set -e

echo "🚀 Starting CPC Test Suite"
echo "=========================="

# Check if we're in virtual environment
if [[ "$VIRTUAL_ENV" != "" ]]; then
    echo "✅ Using virtual environment: $VIRTUAL_ENV"
else
    echo "⚠️  Not using virtual environment"
fi

# Function to run tests
run_tests() {
    local test_type=$1
    local test_path=$2

    echo ""
    echo "📋 Running $test_type tests..."
    echo "------------------------------"

    if python -m pytest "$test_path" -v --tb=short; then
        echo "✅ $test_type tests passed"
        return 0
    else
        echo "❌ $test_type tests failed"
        return 1
    fi
}

# Function to run linting
run_linting() {
    local lint_type=$1
    local command=$2

    echo ""
    echo "🔍 Running $lint_type..."
    echo "------------------------"

    if eval "$command"; then
        echo "✅ $lint_type passed"
        return 0
    else
        echo "⚠️  $lint_type found issues (check output above)"
        return 0  # Don't fail on linting issues for now
    fi
}

# Run all test suites
failed_tests=0

# Unit tests
if run_tests "Unit" "tests/unit/"; then
    echo "✅ Unit tests completed successfully"
else
    echo "❌ Unit tests failed"
    ((failed_tests++))
fi

# Integration tests
if run_tests "Integration" "tests/integration/"; then
    echo "✅ Integration tests completed successfully"
else
    echo "❌ Integration tests failed"
    ((failed_tests++))
fi

# Linting
run_linting "ShellCheck on main script" "shellcheck cpc"
run_linting "Bashate on main script" "bashate cpc"
run_linting "Ansible-lint on playbooks" "ansible-lint ansible/playbooks/"

echo ""
echo "=========================="
echo "🏁 Test Suite Complete"

if [ $failed_tests -eq 0 ]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "⚠️  $failed_tests test suite(s) failed"
    exit 1
fi
