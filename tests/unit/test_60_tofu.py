#!/usr/bin/env python3
"""
Unit tests for refactored functions in modules/60_tofu.sh
"""

import pytest
import subprocess
import os
from pathlib import Path
import shutil


@pytest.fixture
def project_root():
    """Fixture to get the project root path"""
    return Path(__file__).parent.parent.parent


@pytest.fixture
def temp_repo(tmp_path, project_root):
    """Fixture to create a temporary repository structure with real files and mocks"""
    # Create basic structure
    (tmp_path / "modules").mkdir()
    (tmp_path / "lib").mkdir()
    (tmp_path / "envs").mkdir()
    (tmp_path / "terraform").mkdir()
    (tmp_path / "scripts").mkdir()

    # Copy real config.conf
    shutil.copy(project_root / "config.conf", tmp_path / "config.conf")

    # Copy real lib scripts
    lib_dir = project_root / "lib"
    if lib_dir.exists():
        for lib_file in lib_dir.glob("*.sh"):
            shutil.copy(lib_file, tmp_path / "lib" / lib_file.name)

    # Copy the module under test
    shutil.copy(project_root / "modules" / "60_tofu.sh", tmp_path / "modules" / "60_tofu.sh")

    # Create mock modules for isolation
    mock_modules = {
        "00_core.sh": """
#!/bin/bash
function get_current_cluster_context() { echo "test-context"; }
function get_repo_path() { echo "$REPO_PATH"; }
function check_secrets_loaded() { return 0; }
function get_aws_credentials() { echo "true"; }
function error_validate_directory() { return 0; }
function error_handle() { echo "Error: $2"; return 1; }
function log_info() { echo "INFO: $1"; }
function log_success() { echo "SUCCESS: $1"; }
function log_warning() { echo "WARNING: $1"; }
function log_error() { echo "ERROR: $1"; }
function log_debug() { echo "DEBUG: $1"; }
function load_secrets_cached() { return 0; }
function pushd() { return 0; }
function popd() { return 0; }
""",
        "20_ansible.sh": """
#!/bin/bash
function ansible_generate_inventory() { echo "mock inventory"; }
""",
        "30_k8s_cluster.sh": """
#!/bin/bash
function k8s_setup_cluster() { echo "mock k8s setup"; }
""",
        "40_k8s_nodes.sh": """
#!/bin/bash
function k8s_add_nodes() { echo "mock add nodes"; }
""",
        "50_cluster_ops.sh": """
#!/bin/bash
function cluster_status() { echo "mock status"; }
""",
        "80_ssh.sh": """
#!/bin/bash
function ssh_connect() { echo "mock ssh"; }
"""
    }

    for module_name, content in mock_modules.items():
        (tmp_path / "modules" / module_name).write_text(content)

    # Create mock tofu command
    mock_tofu = """#!/bin/bash
    case "$1" in
        workspace)
            case "$2" in
                select)
                    if [[ "$3" == "test-context" ]]; then
                        echo "Switched to workspace test-context"
                        exit 0
                    else
                        echo "Workspace $3 doesn't exist"
                        exit 1
                    fi
                    ;;
                show)
                    echo "test-context"
                    exit 0
                    ;;
            esac
            ;;
        output)
            if [[ "$2" == "-json" && "$3" == "cluster_summary" ]]; then
                echo '{"test-node": {"IP": "10.0.0.1", "hostname": "test-host"}}'
                exit 0
            fi
            ;;
        plan)
            echo "No changes. Your infrastructure matches the configuration."
            exit 0
            ;;
        apply)
            echo "Apply complete!"
            exit 0
            ;;
    esac
    echo "Mock tofu command executed: $@"
    exit 0
    """
    (tmp_path / "mock_tofu").write_text(mock_tofu)
    (tmp_path / "mock_tofu").chmod(0o755)
    
    # Create mock hostname generation script
    mock_hostname_script = """#!/bin/bash
    echo "Generated hostname: test-host"
    echo "SUCCESS: Hostname configurations generated successfully."
    exit 0
    """
    (tmp_path / "scripts" / "generate_node_hostnames.sh").write_text(mock_hostname_script)
    (tmp_path / "scripts" / "generate_node_hostnames.sh").chmod(0o755)

    return tmp_path


@pytest.fixture
def mock_env(temp_repo):
    """Fixture to set up mock environment variables"""
    env = os.environ.copy()
    env['REPO_PATH'] = str(temp_repo)
    env['CPC_WORKSPACE'] = 'test'
    return env


def run_bash_command(command, env=None, cwd=None):
    """Helper to run bash commands with proper sourcing order"""
    # Use relative paths for sourcing
    full_command = f"""
    # Set REPO_PATH to current directory for testing
    export REPO_PATH="{cwd}"
    
    # Source all lib scripts first (using relative paths)
    for lib in lib/*.sh; do
        [ -f "$lib" ] && source "$lib"
    done
    # Source config
    source config.conf
    # Source mock modules
    for module in modules/*.sh; do
        [ -f "$module" ] && source "$module"
    done
    # Execute the command
    {command}
    """
    return subprocess.run(
        ['bash', '-c', full_command],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True
    )


class TestCpcTofu:
    """Test cpc_tofu() - Main dispatcher function"""

    def test_cpc_tofu_deploy_success(self, temp_repo, mock_env):
        """Test successful dispatch to deploy command"""
        result = run_bash_command("cpc_tofu deploy plan", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "INFO:" in result.stdout

    def test_cpc_tofu_invalid_command_failure(self, temp_repo, mock_env):
        """Test failure with invalid command"""
        result = run_bash_command("cpc_tofu invalid-command", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Unknown tofu command" in result.stderr

    def test_cpc_tofu_no_command_edge_case(self, temp_repo, mock_env):
        """Test edge case with no command provided"""
        result = run_bash_command("cpc_tofu", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0


class TestTofuDeploy:
    """Test tofu_deploy() - Deploy command handler"""

    def test_tofu_deploy_plan_success(self, temp_repo, mock_env):
        """Test successful plan deployment"""
        result = run_bash_command("tofu_deploy plan", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_tofu_deploy_invalid_subcommand_failure(self, temp_repo, mock_env):
        """Test failure with invalid subcommand"""
        result = run_bash_command("tofu_deploy invalid", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Error:" in result.stderr

    def test_tofu_deploy_empty_args_edge_case(self, temp_repo, mock_env):
        """Test edge case with empty arguments"""
        result = run_bash_command("tofu_deploy", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0


class TestTofuStartVms:
    """Test tofu_start_vms() - VM startup management"""

    def test_tofu_start_vms_success(self, temp_repo, mock_env):
        """Test successful VM startup"""
        result = run_bash_command("tofu_start_vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_tofu_start_vms_confirmation_failure(self, temp_repo, mock_env):
        """Test failure when user declines confirmation"""
        # Mock user input as 'n'
        env = mock_env.copy()
        env['USER_INPUT'] = 'n'
        result = run_bash_command("echo 'n' | tofu_start_vms", env=env, cwd=temp_repo)
        assert result.returncode == 0  # Function returns 0 on cancellation
        assert "cancelled" in result.stdout.lower()

    def test_tofu_start_vms_no_context_edge_case(self, temp_repo, mock_env):
        """Test edge case with no context"""
        env = mock_env.copy()
        env['CPC_CONTEXT_FILE'] = '/nonexistent'
        result = run_bash_command("tofu_start_vms", env=env, cwd=temp_repo)
        assert result.returncode != 0


class TestTofuStopVms:
    """Test tofu_stop_vms() - VM shutdown management"""

    def test_tofu_stop_vms_success(self, temp_repo, mock_env):
        """Test successful VM shutdown"""
        result = run_bash_command("tofu_stop_vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_tofu_stop_vms_confirmation_failure(self, temp_repo, mock_env):
        """Test failure when user declines confirmation"""
        result = run_bash_command("echo 'n' | tofu_stop_vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "cancelled" in result.stdout.lower()

    def test_tofu_stop_vms_no_context_edge_case(self, temp_repo, mock_env):
        """Test edge case with no context"""
        env = mock_env.copy()
        env['CPC_CONTEXT_FILE'] = '/nonexistent'
        result = run_bash_command("tofu_stop_vms", env=env, cwd=temp_repo)
        assert result.returncode != 0


class TestTofuGenerateHostnames:
    """Test tofu_generate_hostnames() - Hostname generation"""

    def test_tofu_generate_hostnames_success(self, temp_repo, mock_env):
        """Test successful hostname generation"""
        result = run_bash_command("tofu_generate_hostnames", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_tofu_generate_hostnames_script_missing_failure(self, temp_repo, mock_env):
        """Test failure when hostname script is missing"""
        # Remove the script if it exists
        script_path = temp_repo / "scripts" / "generate_node_hostnames.sh"
        if script_path.exists():
            script_path.unlink()
        result = run_bash_command("tofu_generate_hostnames", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0

    def test_tofu_generate_hostnames_no_context_edge_case(self, temp_repo, mock_env):
        """Test edge case with no context"""
        env = mock_env.copy()
        env['CPC_CONTEXT_FILE'] = '/nonexistent'
        result = run_bash_command("tofu_generate_hostnames", env=env, cwd=temp_repo)
        assert result.returncode != 0


class TestTofuShowClusterInfo:
    """Test tofu_show_cluster_info() - Show cluster info"""

    def test_tofu_show_cluster_info_table_success(self, temp_repo, mock_env):
        """Test successful cluster info display in table format"""
        result = run_bash_command("tofu_show_cluster_info", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Available Workspaces" in result.stdout

    def test_tofu_show_cluster_info_json_success(self, temp_repo, mock_env):
        """Test successful cluster info display in JSON format"""
        result = run_bash_command("tofu_show_cluster_info --format json", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0

    def test_tofu_show_cluster_info_invalid_format_failure(self, temp_repo, mock_env):
        """Test failure with invalid format"""
        result = run_bash_command("tofu_show_cluster_info --format invalid", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Error:" in result.stderr


class TestTofuLoadWorkspaceEnvVars:
    """Test tofu_load_workspace_env_vars() - Load workspace environment variables"""

    def test_tofu_load_workspace_env_vars_success(self, temp_repo, mock_env):
        """Test successful environment variable loading"""
        # Create a test env file
        env_file = temp_repo / "envs" / "test-context.env"
        env_file.parent.mkdir(parents=True, exist_ok=True)
        env_file.write_text("TEST_VAR=test_value")

        result = run_bash_command("tofu_load_workspace_env_vars test-context", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Successfully loaded" in result.stdout

    def test_tofu_load_workspace_env_vars_missing_file_failure(self, temp_repo, mock_env):
        """Test failure when env file is missing"""
        result = run_bash_command("tofu_load_workspace_env_vars nonexistent", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0  # Function returns 0 even if file missing
        assert "No environment file found" in result.stdout
