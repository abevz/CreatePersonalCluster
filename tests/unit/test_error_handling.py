import pytest

class TestErrorHandling:
    """Tests for functions in error_handling.sh."""

    def test_error_handle_prints_to_stdout(self, bash_helper):
        """Verify that error_handle prints the message to stdout."""
        result = bash_helper('error_handle "TEST_ERR" "My test error" "HIGH" "abort"')
        assert result.returncode == 1
        assert "My test error" in result.stderr

    def test_error_validate_command_exists_success(self, bash_helper):
        """Verify success when a command exists."""
        result = bash_helper('error_validate_command_exists "ls"')
        assert result.returncode == 0
        assert result.stdout == ""

    def test_error_validate_command_exists_failure(self, bash_helper):
        """Verify failure when a command does not exist."""
        result = bash_helper('error_validate_command_exists "nonexistentcommand12345"')
        assert result.returncode == 1
        assert "[103]" in result.stderr
        assert "Required command 'nonexistentcommand12345' not found" in result.stderr
