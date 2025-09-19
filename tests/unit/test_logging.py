import pytest

class TestLogging:
    """Tests for functions in logging.sh."""

    def test_log_info_prints_to_stdout(self, bash_helper):
        result = bash_helper('log_info "This is an info message"')
        assert result.returncode == 0
        assert "This is an info message" in result.stdout

    def test_log_success_prints_to_stdout(self, bash_helper):
        result = bash_helper('log_success "Operation successful"')
        assert result.returncode == 0
        assert "Operation successful" in result.stdout

    def test_log_warning_prints_to_stderr(self, bash_helper):
        result = bash_helper('log_warning "This is a warning"')
        assert result.returncode == 0
        assert "This is a warning" in result.stderr

    def test_log_error_prints_to_stderr(self, bash_helper):
        result = bash_helper('log_error "This is an error"')
        assert result.returncode == 0
        assert "This is an error" in result.stderr

    def test_log_debug_prints_only_when_cpc_debug_is_true(self, bash_helper):
        result_debug = bash_helper('log_debug "Debug message visible"', env={"CPC_DEBUG": "true"})
        assert "Debug message visible" in result_debug.stdout

        result_no_debug = bash_helper('log_debug "Debug message not visible"')
        assert "Debug message not visible" not in result_no_debug.stdout
