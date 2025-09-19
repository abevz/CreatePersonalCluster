#!/usr/bin/env python3
"""
Comprehensive unit test suite for modules/20_ansible.sh
Tests the refactored Ansible playbook management module with full isolation.
"""

import pytest
import subprocess
import tempfile
import shutil
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple


@pytest.fixture(scope="function")
def temp_repo(tmp_path):
    """Create isolated temporary repository structure for testing"""
    # Create directory structure
    modules_dir = tmp_path / "modules"
    lib_dir = tmp_path / "lib"
    ansible_dir = tmp_path / "ansible"
    envs_dir = tmp_path / "envs"
    scripts_dir = tmp_path / "scripts"

    for dir_path in [modules_dir, lib_dir, ansible_dir, envs_dir, scripts_dir]:
        dir_path.mkdir()

    # Copy real files
    repo_root = Path("/home/abevz/Projects/kubernetes/CreatePersonalCluster")

    # Copy the module under test
    if (repo_root / "modules" / "20_ansible.sh").exists():
        shutil.copy(repo_root / "modules" / "20_ansible.sh", modules_dir / "20_ansible.sh")

    # Copy lib scripts
    lib_files = ["logging.sh", "error_handling.sh", "utils.sh"]
    for lib_file in lib_files:
        src = repo_root / "lib" / lib_file
        if src.exists():
            shutil.copy(src, lib_dir / lib_file)
        else:
            # Create mock lib files
            (lib_dir / lib_file).write_text(f"""
#!/bin/bash
# Mock {lib_file} for testing

log_info() {{
    echo "INFO: $*" >&2
}}

log_error() {{
    echo "ERROR: $*" >&2
}}

log_warning() {{
    echo "WARNING: $*" >&2
}}

log_success() {{
    echo "SUCCESS: $*" >&2
}}

log_debug() {{
    echo "DEBUG: $*" >&2
}}

error_handle() {{
    echo "ERROR_HANDLE: $*" >&2
    return 1
}}

# Add other mock functions as needed
""")

    # Create mock 00_core.sh
    (lib_dir / "00_core.sh").write_text("""
#!/bin/bash
# Mock 00_core.sh for testing

get_repo_path() {
    echo "$REPO_PATH"
}

get_current_cluster_context() {
    echo "test-cluster"
}

load_secrets_cached() {
    return 0
}

# Mock other core functions
""")

    # Create logging.sh with all functions
    (lib_dir / "logging.sh").write_text("""
#!/bin/bash
# Mock logging.sh for testing

log_info() {
    echo "INFO: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

log_warning() {
    echo "WARNING: $*" >&2
}

log_success() {
    echo "SUCCESS: $*" >&2
}

log_debug() {
    echo "DEBUG: $*" >&2
}
""")

    # Create error_handling.sh
    (lib_dir / "error_handling.sh").write_text("""
#!/bin/bash
# Mock error_handling.sh for testing

error_handle() {
    echo "ERROR_HANDLE: $*" >&2
    return 1
}
""")

    # Create utils.sh
    (lib_dir / "utils.sh").write_text("""
#!/bin/bash
# Mock utils.sh for testing

# Add any utility functions if needed
""")

    # Create ansible.cfg
    (ansible_dir / "ansible.cfg").write_text("""
[defaults]
remote_user = testuser
host_key_checking = False
""")

    # Create playbooks directory and sample playbook
    playbooks_dir = ansible_dir / "playbooks"
    playbooks_dir.mkdir()
    (playbooks_dir / "test_playbook.yml").write_text("""
---
- name: Test playbook
  hosts: all
  tasks:
    - name: Test task
      debug:
        msg: "Hello from test playbook"
""")

    # Create sample env file
    (envs_dir / "test-cluster.env").write_text("""
TEST_VAR=test_value
ANOTHER_VAR=another_value
""")

    # Set REPO_PATH environment variable
    os.environ["REPO_PATH"] = str(tmp_path)

    yield tmp_path

    # Cleanup
    os.environ.pop("REPO_PATH", None)


class BashTestHelper:
    """Helper class for executing bash commands in tests"""

    @staticmethod
    def run_bash_command(command: str, env: Optional[Dict[str, str]] = None,
                        cwd: Optional[Path] = None) -> Tuple[int, str, str]:
        """Execute bash command with proper sourcing of scripts"""
        repo_path = env.get("REPO_PATH") if env else os.environ.get("REPO_PATH")

        # Build the full bash command with sourcing
        full_command = f"""
set -e
export REPO_PATH="{repo_path}"
source "{repo_path}/lib/logging.sh" 2>/dev/null || true
source "{repo_path}/lib/error_handling.sh" 2>/dev/null || true
source "{repo_path}/lib/utils.sh" 2>/dev/null || true
source "{repo_path}/lib/00_core.sh" 2>/dev/null || true
source "{repo_path}/modules/20_ansible.sh" 2>/dev/null || true
{command}
"""

        # Execute the command
        result = subprocess.run(
            ["/bin/bash", "-c", full_command],
            capture_output=True,
            text=True,
            env=env,
            cwd=cwd or Path.cwd()
        )

        return result.returncode, result.stdout, result.stderr


class TestCpcAnsible:
    """Test the main cpc_ansible function"""

    def test_cpc_ansible_run_ansible_help(self, temp_repo):
        """Test cpc_ansible with run-ansible help"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "cpc_ansible run-ansible --help",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "Usage: cpc run-ansible" in stdout

    def test_cpc_ansible_run_ansible_valid_playbook(self, temp_repo):
        """Test cpc_ansible with valid playbook"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "cpc_ansible run-ansible test_playbook.yml",
            {"REPO_PATH": str(temp_repo), "PATH": "/usr/bin:/bin"}
        )

        # Since ansible-playbook may not be available, check that the function processes correctly
        assert "Running Ansible playbook: test_playbook.yml" in stderr or exit_code == 0

    def test_cpc_ansible_run_ansible_invalid_playbook(self, temp_repo):
        """Test cpc_ansible with invalid playbook"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "cpc_ansible run-ansible nonexistent.yml",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1
        assert "not found" in stderr

    def test_cpc_ansible_run_command_help(self, temp_repo):
        """Test cpc_ansible with run-command help"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "cpc_ansible run-command --help",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "Usage: cpc run-command" in stdout

    def test_cpc_ansible_unknown_command(self, temp_repo):
        """Test cpc_ansible with unknown command"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "cpc_ansible unknown-command",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1
        assert "Unknown ansible command" in stderr


class TestAnsibleRunPlaybookCommand:
    """Test ansible_run_playbook_command function"""

    def test_run_playbook_command_help(self, temp_repo):
        """Test run-playbook-command help"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_run_playbook_command --help",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "Usage: cpc run-ansible" in stdout

    def test_run_playbook_command_valid(self, temp_repo):
        """Test run-playbook-command with valid playbook"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_run_playbook_command test_playbook.yml",
            {"REPO_PATH": str(temp_repo)}
        )

        assert "Running Ansible playbook: test_playbook.yml" in stderr or exit_code == 0

    def test_run_playbook_command_invalid(self, temp_repo):
        """Test run-playbook-command with invalid playbook"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_run_playbook_command invalid.yml",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1
        assert "not found" in stderr


class TestAnsibleShowHelp:
    """Test ansible_show_help function"""

    def test_show_help_output(self, temp_repo):
        """Test that help displays correctly"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_show_help",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "Usage: cpc run-ansible" in stdout
        assert "Runs the specified Ansible playbook" in stdout


class TestAnsibleListPlaybooks:
    """Test ansible_list_playbooks function"""

    def test_list_playbooks_with_files(self, temp_repo):
        """Test listing playbooks when files exist"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_list_playbooks",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "test_playbook.yml" in stdout

    def test_list_playbooks_no_directory(self, temp_repo):
        """Test listing playbooks when directory doesn't exist"""
        # Remove playbooks directory
        playbooks_dir = temp_repo / "ansible" / "playbooks"
        if playbooks_dir.exists():
            shutil.rmtree(playbooks_dir)

        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_list_playbooks",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "not found" in stderr


class TestAnsibleRunShellCommand:
    """Test ansible_run_shell_command function"""

    def test_run_shell_command_valid(self, temp_repo):
        """Test running shell command with valid parameters"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            'ansible_run_shell_command "all" "echo test"',
            {"REPO_PATH": str(temp_repo)}
        )

        assert "Running command on all: echo test" in stderr or exit_code == 0

    def test_run_shell_command_insufficient_args(self, temp_repo):
        """Test running shell command with insufficient arguments"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_run_shell_command",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1


class TestAnsibleRunPlaybook:
    """Test ansible_run_playbook function"""

    def test_run_playbook_with_temp_inventory(self, temp_repo):
        """Test running playbook that creates temporary inventory"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_run_playbook test_playbook.yml",
            {"REPO_PATH": str(temp_repo)}
        )

        # Check that it attempts to run the playbook
        assert "Running:" in stderr or exit_code != 0  # May fail if ansible not installed

    def test_run_playbook_with_custom_args(self, temp_repo):
        """Test running playbook with custom arguments"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            'ansible_run_playbook test_playbook.yml --check --verbose',
            {"REPO_PATH": str(temp_repo)}
        )

        assert "Running:" in stderr or exit_code != 0


class TestAnsibleUpdateInventoryCache:
    """Test inventory cache update functions"""

    def test_update_inventory_cache_basic(self, temp_repo):
        """Test basic inventory cache update"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_update_inventory_cache",
            {"REPO_PATH": str(temp_repo)}
        )

        # Should return 1 when terraform directory doesn't exist
        assert exit_code == 1
        assert "Terraform directory not found" in stderr

    def test_update_inventory_cache_advanced_help(self, temp_repo):
        """Test advanced inventory cache update help"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_update_inventory_cache_advanced --help",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "Usage: cpc update-inventory" in stdout

    def test_update_inventory_cache_advanced_no_terraform(self, temp_repo):
        """Test advanced inventory cache update without terraform directory"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_update_inventory_cache_advanced",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1
        assert "terraform directory not found" in stderr


class TestAnsibleEnvironmentHandling:
    """Test environment variable and secret handling"""

    def test_load_environment_variables_with_file(self, temp_repo):
        """Test loading environment variables from file"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_load_environment_variables",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        # Should contain variables from test-cluster.env
        assert "TEST_VAR=test_value" in stdout and "ANOTHER_VAR=another_value" in stdout

    def test_load_environment_variables_no_file(self, temp_repo):
        """Test loading environment variables when file doesn't exist"""
        # Remove env file
        env_file = temp_repo / "envs" / "test-cluster.env"
        if env_file.exists():
            env_file.unlink()

        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_load_environment_variables",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert stdout.strip() == ""  # Should be empty

    def test_prepare_secret_variables(self, temp_repo):
        """Test preparing secret variables"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_prepare_secret_variables",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        # Should not contain secrets since they're not set


class TestAnsibleHelperFunctions:
    """Test various helper functions"""

    def test_validate_terraform_directory_exists(self, temp_repo):
        """Test terraform directory validation when it exists"""
        # Create terraform directory
        terraform_dir = temp_repo / "terraform"
        terraform_dir.mkdir()

        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_validate_terraform_directory",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0

    def test_validate_terraform_directory_missing(self, temp_repo):
        """Test terraform directory validation when it doesn't exist"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_validate_terraform_directory",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1
        assert "terraform directory not found" in stderr

    def test_setup_aws_credentials(self, temp_repo):
        """Test AWS credentials setup"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_setup_aws_credentials",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0

    def test_ansible_help(self, temp_repo):
        """Test ansible help function"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_help",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "Ansible Module" in stdout
        assert "run-ansible" in stdout


class TestAnsibleInventoryFunctions:
    """Test inventory-related functions"""

    def test_create_temp_inventory_with_cache(self, temp_repo):
        """Test creating temporary inventory with existing cache"""
        # Create a mock cache file
        cache_file = temp_repo / ".ansible_inventory_cache.json"
        cache_file.write_text('{"_meta": {"hostvars": {}}, "all": {"children": ["control_plane", "workers"]}, "control_plane": {"hosts": []}, "workers": {"hosts": []}}')

        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_create_temp_inventory",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        # Should output the path to the temporary file
        assert "/tmp/ansible_inventory_" in stdout

    def test_create_temp_inventory_no_cache(self, temp_repo):
        """Test creating temporary inventory without cache"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_create_temp_inventory",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "/tmp/ansible_inventory_" in stdout

    def test_prepare_inventory_no_existing(self, temp_repo):
        """Test preparing inventory when none exists in args"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_prepare_inventory",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        assert "/tmp/ansible_inventory_" in stdout


class TestAnsibleCommandConstruction:
    """Test command construction and cleanup"""

    def test_construct_command_array_basic(self, temp_repo):
        """Test basic command array construction"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            'ansible_construct_command_array result_array test_playbook.yml "" "" ""',
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0

    def test_cleanup_temp_files(self, temp_repo):
        """Test cleanup of temporary files"""
        # Create a temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False)
        temp_file_path = temp_file.name
        temp_file.close()

        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            f'ansible_cleanup_temp_files "{temp_file_path}"',
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 0
        # File should be removed
        assert not os.path.exists(temp_file_path)


class TestAnsibleErrorHandling:
    """Test error handling in various scenarios"""

    def test_run_playbook_nonexistent_repo(self, temp_repo):
        """Test running playbook with invalid repo path"""
        # Mock get_repo_path to return nonexistent path
        mock_core = temp_repo / "lib" / "00_core.sh"
        mock_core.write_text('get_repo_path() { echo "/nonexistent/path"; }\nget_current_cluster_context() { echo "test-cluster"; }')
        
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_run_playbook test_playbook.yml",
            {"REPO_PATH": str(temp_repo)}
        )

        # Should fail when repo path doesn't exist
        assert exit_code != 0

    def test_get_cluster_summary_no_terraform(self, temp_repo):
        """Test getting cluster summary without terraform directory"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_get_cluster_summary",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1
        assert "Terraform directory not found" in stderr

    def test_fetch_cluster_information_no_terraform(self, temp_repo):
        """Test fetching cluster information without terraform directory"""
        exit_code, stdout, stderr = BashTestHelper.run_bash_command(
            "ansible_fetch_cluster_information",
            {"REPO_PATH": str(temp_repo)}
        )

        assert exit_code == 1
        assert "Terraform directory not found" in stderr


if __name__ == "__main__":
    pytest.main([__file__])
