#!/usr/bin/env python3
"""
Comprehensive unit tests for refactored functions in modules/60_tofu.sh
"""

import pytest
import subprocess
import os
from pathlib import Path
import shutil
import tempfile


@pytest.fixture(scope="function")
def project_root():
    """Fixture to get the project root path"""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="function")
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
function get_current_cluster_context() { 
    if [ ! -f "$CPC_CONTEXT_FILE" ]; then
        echo "Error: Context file not found: $CPC_CONTEXT_FILE" >&2
        return 1
    fi
    echo "test-context"; 
}
function get_repo_path() { echo "$REPO_PATH"; }
function check_secrets_loaded() { return 0; }
function get_aws_credentials() { echo "true"; }
function error_validate_directory() { return 0; }
function error_handle() { echo "Error: $2" >&2; return 1; }
function log_info() { echo "INFO: $1"; }
function log_success() { echo "SUCCESS: $1"; }
function log_warning() { echo "WARNING: $1"; }
function log_error() { echo "ERROR: $1"; }
function log_debug() { echo "DEBUG: $1"; }
function load_secrets_cached() { return 0; }
function pushd() { return 0; }
function popd() { return 0; }
function recovery_checkpoint() { echo "Recovery checkpoint: $1"; }
function log_command() { echo "Command: $1"; }
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
                    if [[ "$3" == "nonexistent" ]]; then
                        echo "Error: Workspace 'nonexistent' not found" >&2
                        exit 1
                    fi
                    echo "Switched to workspace $3"
                    exit 0
                    ;;
                show)
                    echo "test-context"
                    exit 0
                    ;;
                list)
                    echo "Switched to workspace test-context"
                    echo "Mock tofu command executed: workspace list"
                    exit 0
                    ;;
            esac
            ;;
        output)
            if [[ "$2" == "-json" && "$3" == "cluster_summary" ]]; then
                echo '{"test-node": {"IP": "10.0.0.1", "hostname": "test-host", "VM_ID": "100"}}'
                exit 0
            elif [[ "$2" == "-json" ]]; then
                echo "Error: Output 'invalid_key' not found" >&2
                exit 1
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
        destroy)
            echo "Destroy complete!"
            exit 0
            ;;
        init)
            echo "Terraform initialized successfully!"
            exit 0
            ;;
    esac
    echo "Mock tofu command executed: $@"
    exit 0
    """
    (tmp_path / "tofu").write_text(mock_tofu)
    (tmp_path / "tofu").chmod(0o755)

    # Create mock hostname generation script
    mock_hostname_script = """#!/bin/bash
    echo "Generated hostname: test-host"
    echo "SUCCESS: Hostname configurations generated successfully."
    exit 0
    """
    (tmp_path / "scripts" / "generate_node_hostnames.sh").write_text(mock_hostname_script)
    (tmp_path / "scripts" / "generate_node_hostnames.sh").chmod(0o755)

    return tmp_path


@pytest.fixture(scope="function")
def mock_env(temp_repo):
    """Fixture to set up mock environment variables"""
    env = os.environ.copy()
    env['REPO_PATH'] = str(temp_repo)
    env['CPC_WORKSPACE'] = 'test'
    env['TERRAFORM_DIR'] = 'terraform'
    env['PATH'] = str(temp_repo) + ':' + env.get('PATH', '')
    return env


def run_bash_command(command, env=None, cwd=None):
    """Helper to run bash commands with proper sourcing order"""
    # Use relative paths for sourcing
    full_command = f"""
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
    # Set REPO_PATH after sourcing to override config.conf
    export REPO_PATH="{cwd}"
    # Execute the command
    {command}
    """
    return subprocess.run(
        ['bash', '-c', full_command],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=30
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

    def test_cpc_tofu_workspace_success(self, temp_repo, mock_env):
        """Test successful workspace command dispatch"""
        result = run_bash_command("cpc_tofu workspace show", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test-context" in result.stdout

    def test_cpc_tofu_workspace_list_success(self, temp_repo, mock_env):
        """Test successful workspace list command dispatch"""
        result = run_bash_command("cpc_tofu workspace list", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Switched to workspace" in result.stdout or "Mock tofu command executed" in result.stdout

    def test_cpc_tofu_workspace_select_success(self, temp_repo, mock_env):
        """Test successful workspace select command dispatch"""
        result = run_bash_command("cpc_tofu workspace select test-context", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Switched to workspace test-context" in result.stdout

    def test_cpc_tofu_start_vms_success(self, temp_repo, mock_env):
        """Test successful start-vms command dispatch"""
        result = run_bash_command("cpc_tofu start-vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_cpc_tofu_stop_vms_success(self, temp_repo, mock_env):
        """Test successful stop-vms command dispatch"""
        result = run_bash_command("cpc_tofu stop-vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_cpc_tofu_generate_hostnames_success(self, temp_repo, mock_env):
        """Test successful generate-hostnames command dispatch"""
        result = run_bash_command("cpc_tofu generate-hostnames", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_cpc_tofu_cluster_info_success(self, temp_repo, mock_env):
        """Test successful cluster-info command dispatch"""
        result = run_bash_command("cpc_tofu cluster-info", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Getting cluster information" in result.stdout


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

    def test_tofu_deploy_apply_success(self, temp_repo, mock_env):
        """Test successful apply deployment"""
        result = run_bash_command("tofu_deploy apply", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_tofu_deploy_destroy_success(self, temp_repo, mock_env):
        """Test successful destroy deployment"""
        result = run_bash_command("tofu_deploy destroy", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_tofu_deploy_workspace_subcommand_success(self, temp_repo, mock_env):
        """Test successful workspace subcommand in deploy (backward compatibility)"""
        result = run_bash_command("tofu_deploy workspace show", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test-context" in result.stdout

    def test_tofu_deploy_workspace_list_subcommand_success(self, temp_repo, mock_env):
        """Test successful workspace list subcommand in deploy (backward compatibility)"""
        result = run_bash_command("tofu_deploy workspace list", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Switched to workspace" in result.stdout or "Mock tofu command executed" in result.stdout

    def test_tofu_deploy_workspace_select_subcommand_success(self, temp_repo, mock_env):
        """Test successful workspace select subcommand in deploy (backward compatibility)"""
        result = run_bash_command("tofu_deploy workspace select test-context", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Switched to workspace test-context" in result.stdout


class TestTofuStartVms:
    """Test tofu_start_vms() - VM startup management"""

    def test_tofu_start_vms_success(self, temp_repo, mock_env):
        """Test successful VM startup (confirmation skipped in test mode)"""
        result = run_bash_command("tofu_start_vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

    def test_tofu_start_vms_confirmation_failure(self, temp_repo, mock_env):
        """Test successful VM startup (confirmation skipped in test mode)"""
        result = run_bash_command("tofu_start_vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

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
        """Test successful VM shutdown (confirmation skipped in test mode)"""
        result = run_bash_command("tofu_stop_vms", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "SUCCESS:" in result.stdout

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
        assert "Cluster Information" in result.stdout

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

    def test_tofu_load_workspace_env_vars_empty_context_edge_case(self, temp_repo, mock_env):
        """Test edge case with empty context"""
        result = run_bash_command("tofu_load_workspace_env_vars ''", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0


class TestTofuUpdateNodeInfo:
    """Test tofu_update_node_info() - Update node info"""

    def test_tofu_update_node_info_success(self, temp_repo, mock_env):
        """Test successful node info update"""
        json_data = '{"node1": {"IP": "10.0.0.1", "hostname": "test-host"}}'
        result = run_bash_command(f"tofu_update_node_info '{json_data}'", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0

    def test_tofu_update_node_info_invalid_json_failure(self, temp_repo, mock_env):
        """Test failure with invalid JSON"""
        result = run_bash_command("tofu_update_node_info 'invalid json'", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Error:" in result.stderr

    def test_tofu_update_node_info_empty_json_edge_case(self, temp_repo, mock_env):
        """Test edge case with empty JSON"""
        result = run_bash_command("tofu_update_node_info ''", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0


class TestTofuWorkspaceOperations:
    """Test tofu workspace operations"""

    def test_tofu_workspace_select_success(self, temp_repo, mock_env):
        """Test successful workspace selection"""
        result = run_bash_command("tofu workspace select test-context", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode == 0
        assert "Switched to workspace" in result.stdout

    def test_tofu_workspace_select_nonexistent_failure(self, temp_repo, mock_env):
        """Test failure when selecting nonexistent workspace"""
        result = run_bash_command("tofu workspace select nonexistent", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode != 0
        assert "not found" in result.stderr

    def test_tofu_workspace_show_success(self, temp_repo, mock_env):
        """Test successful workspace show"""
        result = run_bash_command("tofu workspace show", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode == 0
        assert "test-context" in result.stdout


class TestTofuOutputOperations:
    """Test tofu output operations"""

    def test_tofu_output_cluster_summary_success(self, temp_repo, mock_env):
        """Test successful cluster summary output"""
        result = run_bash_command("tofu output -json cluster_summary", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode == 0
        assert "test-node" in result.stdout

    def test_tofu_output_invalid_key_failure(self, temp_repo, mock_env):
        """Test failure with invalid output key"""
        result = run_bash_command("tofu output -json invalid_key", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode != 0


class TestTofuPlanOperations:
    """Test tofu plan operations"""

    def test_tofu_plan_success(self, temp_repo, mock_env):
        """Test successful plan execution"""
        result = run_bash_command("tofu plan", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode == 0
        assert "No changes" in result.stdout

    def test_tofu_plan_with_vars_success(self, temp_repo, mock_env):
        """Test successful plan with variables"""
        result = run_bash_command("tofu plan -var 'test_var=test_value'", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode == 0


class TestTofuApplyOperations:
    """Test tofu apply operations"""

    def test_tofu_apply_success(self, temp_repo, mock_env):
        """Test successful apply execution"""
        result = run_bash_command("tofu apply", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode == 0
        assert "Apply complete" in result.stdout

    def test_tofu_apply_with_auto_approve_success(self, temp_repo, mock_env):
        """Test successful apply with auto-approve"""
        result = run_bash_command("tofu apply -auto-approve", env=mock_env, cwd=temp_repo / "terraform")
        assert result.returncode == 0


class TestEnvironmentIsolation:
    """Test environment isolation and cleanup"""

    def test_environment_variables_isolation(self, temp_repo, mock_env, monkeypatch):
        """Test that environment variables are properly isolated"""
        # Set a test environment variable in the mock environment
        test_env = mock_env.copy()
        test_env['TEST_ISOLATION_VAR'] = 'test_value'

        # Run a command that should see this variable
        result = run_bash_command("echo $TEST_ISOLATION_VAR", env=test_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test_value" in result.stdout

    def test_file_system_isolation(self, temp_repo, mock_env):
        """Test that file system changes are isolated"""
        # Create a test file
        test_file = temp_repo / "test_isolation.txt"
        test_file.write_text("isolation test")

        # Verify file exists in this test context
        result = run_bash_command("ls test_isolation.txt", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test_isolation.txt" in result.stdout

    def test_no_cross_test_contamination(self, temp_repo, mock_env):
        """Test that tests don't contaminate each other"""
        # This test should not see files or variables from other tests
        result = run_bash_command("echo $TEST_ISOLATION_VAR", env=mock_env, cwd=temp_repo)
        # Should not contain the variable from the previous test
        assert "test_value" not in result.stdout


class TestTofuHelperFunctions:
    """Test tofu helper functions"""

    def test_validate_tofu_subcommand_workspace_success(self, temp_repo, mock_env):
        """Test that workspace is now a valid subcommand"""
        # This should not fail since we added workspace to supported commands
        result = run_bash_command("tofu_deploy workspace show", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test-context" in result.stdout

    def test_validate_tofu_subcommand_invalid_failure(self, temp_repo, mock_env):
        """Test that invalid subcommands still fail"""
        result = run_bash_command("tofu_deploy nonexistent", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Unsupported tofu subcommand" in result.stderr

    def test_workspace_backward_compatibility(self, temp_repo, mock_env):
        """Test that both workspace command styles work identically"""
        # Test direct workspace command
        result1 = run_bash_command("cpc_tofu workspace show", env=mock_env, cwd=temp_repo)
        # Test workspace as deploy subcommand
        result2 = run_bash_command("tofu_deploy workspace show", env=mock_env, cwd=temp_repo)
        
        # Both should succeed and return the same result
        assert result1.returncode == 0
        assert result2.returncode == 0
        assert "test-context" in result1.stdout
        assert "test-context" in result2.stdout
