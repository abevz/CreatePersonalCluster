import pytest

class TestValidateWorkspaceName:
    """Tests for the validate_workspace_name function in utils.sh."""

    @pytest.mark.parametrize("valid_name", ["my-workspace", "workspace_1", "123", "a"])
    def test_valid_names(self, bash_helper, valid_name):
        """Test that valid workspace names pass validation."""
        result = bash_helper(f'validate_workspace_name "{valid_name}"')
        assert result.returncode == 0, f"Valid name '{valid_name}' failed validation. Stderr: {result.stderr}"

    @pytest.mark.parametrize("invalid_name, error_message", [
        ("", "between 1 and 50 characters"),
        ("a" * 51, "between 1 and 50 characters"),
        ("invalid name", "contain letters, numbers, hyphens, and underscores"),
        ("test!", "contain letters, numbers, hyphens, and underscores"),
        ("default", "is reserved"),
        ("null", "is reserved"),
    ])
    def test_invalid_names(self, bash_helper, invalid_name, error_message):
        """Test that invalid workspace names fail validation with the correct message."""
        result = bash_helper(f'validate_workspace_name "{invalid_name}"')
        assert result.returncode != 0, f"Invalid name '{invalid_name}' passed validation."
        assert error_message in result.stderr
