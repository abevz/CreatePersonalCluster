import pytest

class TestTofuDeployHelpers:
    """Tests for functions in tofu_deploy_helpers.sh."""

    @pytest.mark.parametrize("subcommand", ["plan", "apply", "destroy"])
    def test_validate_tofu_subcommand_success(self, bash_helper, subcommand):
        """Test that valid subcommands pass."""
        result = bash_helper(f'validate_tofu_subcommand "{subcommand}"')
        assert result.returncode == 0

    def test_validate_tofu_subcommand_failure(self, bash_helper):
        """Test that an invalid subcommand fails."""
        result = bash_helper('validate_tofu_subcommand "invalid-command"')
        assert result.returncode != 0
        assert "Unsupported tofu subcommand" in result.stderr

class TestTofuClusterHelpers:
    """Tests for functions in tofu_cluster_helpers.sh."""

    def test_parse_cluster_json_success(self, bash_helper):
        """Test that valid JSON is parsed correctly."""
        json_input = '{"value":{"node1":{"IP":"1.1.1.1"}}}'
        result = bash_helper(f"parse_cluster_json '{json_input}'")
        assert result.returncode == 0
        assert '"IP": "1.1.1.1"' in result.stdout

    def test_parse_cluster_json_failure(self, bash_helper):
        """Test that null or empty JSON fails."""
        result = bash_helper("parse_cluster_json 'null'")
        assert result.returncode != 0
        assert "No cluster summary available" in result.stderr

class TestTofuEnvHelpers:
    """Tests for functions in tofu_env_helpers.sh."""

    def test_validate_env_file_success(self, bash_helper, tmp_path):
        """Test that an existing file is validated."""
        env_file = tmp_path / "test.env"
        env_file.touch()
        result = bash_helper(f"validate_env_file '{env_file}'")
        assert result.returncode == 0

    def test_validate_env_file_failure(self, bash_helper):
        """Test that a non-existent file fails validation."""
        result = bash_helper("validate_env_file '/non/existent/file'")
        assert result.returncode != 0
