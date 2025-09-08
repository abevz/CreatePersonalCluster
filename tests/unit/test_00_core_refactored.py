#!/usr/bin/env python3
"""
Comprehensive unit tests for refactored functions in modules/00_core.sh
"""

import pytest
import subprocess
import tempfile
import os
import json
from pathlib import Path


@pytest.fixture
def project_root():
    """Fixture to get the project root path"""
    return Path(__file__).parent.parent.parent


@pytest.fixture
def temp_repo(tmp_path):
    """Fixture to create a temporary repository structure"""
    # Create basic structure
    (tmp_path / "modules").mkdir()
    (tmp_path / "lib").mkdir()
    (tmp_path / "envs").mkdir()
    (tmp_path / "terraform").mkdir()
    (tmp_path / "scripts").mkdir()
    
    # Copy necessary files
    project_root = Path(__file__).parent.parent.parent
    import shutil
    shutil.copy(project_root / "config.conf", tmp_path / "config.conf")
    shutil.copy(project_root / "modules" / "00_core.sh", tmp_path / "modules" / "00_core.sh")
    
    # Copy all real lib files
    lib_files = [
        "logging.sh",
        "error_handling.sh", 
        "pihole_api.sh",
        "recovery.sh",
        "retry.sh",
        "ssh_utils.sh",
        "timeout.sh"
    ]
    for lib_file in lib_files:
        src = project_root / "lib" / lib_file
        if src.exists():
            shutil.copy(src, tmp_path / "lib" / lib_file)
    
    return tmp_path


@pytest.fixture
def mock_env(temp_repo):
    """Fixture to set up mock environment variables"""
    env = os.environ.copy()
    env['REPO_PATH'] = str(temp_repo)
    env['CPC_WORKSPACE'] = 'test'
    return env


def run_bash_command(command, env=None, cwd=None):
    """Helper to run bash commands with proper sourcing"""
    full_command = f"""
    source {cwd}/config.conf
    # Source all lib files
    for lib in {cwd}/lib/*.sh; do
        [ -f "$lib" ] && source "$lib"
    done
    source {cwd}/modules/00_core.sh
    {command}
    """
    return subprocess.run(
        ['bash', '-c', full_command],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True
    )


class TestCpcCoreDispatcher:
    """Test cpc_core() - Main Dispatcher"""
    
    def test_dispatcher_setup_cpc_success(self, temp_repo, mock_env):
        """Test successful dispatch to setup-cpc"""
        result = run_bash_command("cpc_core setup-cpc", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "cpc setup complete" in result.stdout

    def test_dispatcher_invalid_command_error(self, temp_repo, mock_env):
        """Test error handling for invalid command"""
        result = run_bash_command("cpc_core invalid", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Unknown core command" in result.stdout


class TestGetRepoPath:
    """Test get_repo_path() - Get Repository Path"""
    
    def test_get_repo_path_success(self, temp_repo, mock_env):
        """Test successful repository path retrieval"""
        result = run_bash_command("get_repo_path && echo $?", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert str(temp_repo) in result.stdout

    def test_get_repo_path_missing_config_error(self, tmp_path, mock_env):
        """Test error when config.conf is missing"""
        # Create modules directory if it doesn't exist
        modules_dir = tmp_path / "modules"
        modules_dir.mkdir(exist_ok=True)
        # Copy the module file
        import shutil
        project_root = Path(__file__).parent.parent.parent
        shutil.copy(project_root / "modules" / "00_core.sh", modules_dir / "00_core.sh")
        
        # Create a custom run_bash_command that doesn't source config.conf
        def run_bash_command_no_config(command, env=None, cwd=None):
            full_command = f"""
            # Source all lib files
            for lib in {cwd}/lib/*.sh; do
                [ -f "$lib" ] && source "$lib"
            done
            source {cwd}/modules/00_core.sh
            {command}
            """
            return subprocess.run(
                ['bash', '-c', full_command],
                cwd=cwd,
                env=env,
                capture_output=True,
                text=True
            )
        
        # Copy lib files
        lib_dir = tmp_path / "lib"
        lib_dir.mkdir(exist_ok=True)
        lib_files = ["logging.sh", "error_handling.sh"]
        for lib_file in lib_files:
            src = project_root / "lib" / lib_file
            if src.exists():
                shutil.copy(src, lib_dir / lib_file)
        
        result = run_bash_command_no_config("get_repo_path", env=mock_env, cwd=tmp_path)
        assert result.returncode != 0
        assert "Invalid repository path" in result.stdout


class TestLoadSecretsCached:
    """Test load_secrets_cached() - Load Secrets with Caching"""
    
    def test_load_secrets_cached_success(self, temp_repo, mock_env, monkeypatch):
        """Test successful cached secrets loading"""
        # Create mock secrets file
        secrets_file = temp_repo / "terraform" / "secrets.sops.yaml"
        secrets_file.parent.mkdir(parents=True, exist_ok=True)
        secrets_file.write_text("mock_secrets: test")
        
        # Mock sops command
        def mock_sops(*args, **kwargs):
            return subprocess.CompletedProcess(args=['sops'], returncode=0, stdout='PROXMOX_HOST: test\n')
        
        monkeypatch.setattr(subprocess, 'run', mock_sops)
        
        result = run_bash_command("load_secrets_cached", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Secrets loaded successfully" in result.stdout

    def test_load_secrets_cached_missing_file_error(self, temp_repo, mock_env):
        """Test error when secrets file is missing"""
        result = run_bash_command("load_secrets_cached", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Secrets file not found" in result.stderr


class TestLoadSecretsFresh:
    """Test load_secrets_fresh() - Load Secrets without Caching"""
    
    def test_load_secrets_fresh_success(self, temp_repo, mock_env, monkeypatch):
        """Test successful fresh secrets loading"""
        # Create mock secrets file
        secrets_file = temp_repo / "terraform" / "secrets.sops.yaml"
        secrets_file.parent.mkdir(parents=True, exist_ok=True)
        secrets_file.write_text("mock_secrets: test")
        
        # Mock sops command
        def mock_sops(*args, **kwargs):
            return subprocess.CompletedProcess(args=['sops'], returncode=0, stdout='PROXMOX_HOST: test\n')
        
        monkeypatch.setattr(subprocess, 'run', mock_sops)
        
        result = run_bash_command("load_secrets_fresh", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Secrets loaded successfully" in result.stdout

    def test_load_secrets_fresh_missing_file_error(self, temp_repo, mock_env):
        """Test error when secrets file is missing"""
        result = run_bash_command("load_secrets_fresh", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Secrets file not found" in result.stderr


class TestLoadEnvVars:
    """Test load_env_vars() - Load Environment Variables"""
    
    def test_load_env_vars_success(self, temp_repo, mock_env):
        """Test successful environment variable loading"""
        # Create mock env file for the default context
        env_file = temp_repo / "envs" / "default.env"
        env_file.parent.mkdir(parents=True, exist_ok=True)
        env_file.write_text("TEST_VAR=test_value\n")
        
        result = run_bash_command("load_env_vars && echo $TEST_VAR", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test_value" in result.stdout

    def test_load_env_vars_missing_file_success(self, temp_repo, mock_env):
        """Test graceful handling when env file doesn't exist"""
        result = run_bash_command("load_env_vars", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0  # Should not fail


class TestSetWorkspaceTemplateVars:
    """Test set_workspace_template_vars() - Set Template Variables"""
    
    def test_set_workspace_template_vars_success(self, temp_repo, mock_env):
        """Test successful template variable setting"""
        # Create mock env file with template vars
        env_file = temp_repo / "envs" / "test.env"
        env_file.parent.mkdir(parents=True, exist_ok=True)
        env_file.write_text("TEMPLATE_VM_ID=9999\nTEMPLATE_VM_NAME=test-template\n")
        
        result = run_bash_command("set_workspace_template_vars test && echo $TEMPLATE_VM_ID", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "9999" in result.stdout

    def test_set_workspace_template_vars_missing_file_success(self, temp_repo, mock_env):
        """Test graceful handling when env file doesn't exist"""
        result = run_bash_command("set_workspace_template_vars nonexistent", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0  # Should not fail


class TestGetCurrentClusterContext:
    """Test get_current_cluster_context() - Get Current Cluster Context"""
    
    def test_get_current_cluster_context_success(self, temp_repo, mock_env):
        """Test successful context retrieval"""
        # Create mock context file at the expected location
        context_file = temp_repo / ".cluster_context"
        context_file.write_text("test-context")
        
        result = run_bash_command("get_current_cluster_context", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test-context" in result.stdout

    def test_get_current_cluster_context_missing_file_success(self, temp_repo, mock_env):
        """Test fallback when context file doesn't exist"""
        env = mock_env.copy()
        env['CPC_CONTEXT_FILE'] = str(temp_repo / "nonexistent")
        
        result = run_bash_command("get_current_cluster_context", env=env, cwd=temp_repo)
        assert result.returncode == 0
        assert "default" in result.stdout


class TestSetClusterContext:
    """Test set_cluster_context() - Set Cluster Context"""
    
    def test_set_cluster_context_success(self, temp_repo, mock_env):
        """Test successful context setting"""
        result = run_bash_command("set_cluster_context new-context", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Cluster context set to: new-context" in result.stdout
        
        # Verify file was created
        context_file = temp_repo / ".cluster_context"
        assert context_file.exists()
        assert context_file.read_text().strip() == "new-context"

    def test_set_cluster_context_invalid_name_error(self, temp_repo, mock_env):
        """Test error with invalid context name"""
        result = run_bash_command("set_cluster_context invalid@context", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Invalid context name" in result.stdout


class TestValidateWorkspaceName:
    """Test validate_workspace_name() - Validate Workspace Name"""
    
    def test_validate_workspace_name_success(self, temp_repo, mock_env):
        """Test successful validation of valid name"""
        result = run_bash_command("validate_workspace_name valid-name", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0

    def test_validate_workspace_name_invalid_error(self, temp_repo, mock_env):
        """Test error with invalid name"""
        result = run_bash_command("validate_workspace_name invalid@name", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Invalid workspace name format" in result.stdout


class TestCoreCtx:
    """Test core_ctx() - Handle Context Command"""
    
    def test_core_ctx_help_success(self, temp_repo, mock_env):
        """Test help output"""
        result = run_bash_command("core_ctx --help", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Usage: cpc ctx" in result.stdout

    def test_core_ctx_set_context_success(self, temp_repo, mock_env):
        """Test setting new context"""
        result = run_bash_command("core_ctx new-context", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Cluster context set to: new-context" in result.stdout


class TestCoreSetupCpc:
    """Test core_setup_cpc() - Setup CPC"""
    
    def test_core_setup_cpc_success(self, temp_repo, mock_env):
        """Test successful CPC setup"""
        result = run_bash_command("core_setup_cpc", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "cpc setup complete" in result.stdout
        
        # Verify repo path file was created
        repo_path_file = Path.home() / ".config" / "cpc" / "repo_path"
        assert repo_path_file.exists()


class TestCoreCloneWorkspace:
    """Test core_clone_workspace() - Clone Workspace"""
    
    def test_core_clone_workspace_help_success(self, temp_repo, mock_env):
        """Test help output"""
        result = run_bash_command("core_clone_workspace --help", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Usage: cpc clone-workspace" in result.stdout

    def test_core_clone_workspace_missing_args_error(self, temp_repo, mock_env):
        """Test error with missing arguments"""
        result = run_bash_command("core_clone_workspace", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0  # It shows help and returns 0
        assert "Usage: cpc clone-workspace" in result.stdout


class TestCoreDeleteWorkspace:
    """Test core_delete_workspace() - Delete Workspace"""
    
    def test_core_delete_workspace_missing_args_error(self, temp_repo, mock_env):
        """Test error with missing arguments"""
        result = run_bash_command("core_delete_workspace", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Usage: cpc delete-workspace" in result.stdout


class TestCoreLoadSecretsCommand:
    """Test core_load_secrets_command() - Load Secrets Command"""
    
    def test_core_load_secrets_command_success(self, temp_repo, mock_env, monkeypatch):
        """Test successful secrets loading command"""
        # Mock secrets loading
        def mock_load_secrets_fresh(*args, **kwargs):
            return subprocess.CompletedProcess(args=['load_secrets_fresh'], returncode=0, stdout='')
        
        monkeypatch.setattr(subprocess, 'run', mock_load_secrets_fresh)
        
        result = run_bash_command("core_load_secrets_command", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Secrets reloaded successfully" in result.stdout


class TestCoreClearCache:
    """Test core_clear_cache() - Clear Cache"""
    
    def test_core_clear_cache_success(self, temp_repo, mock_env):
        """Test successful cache clearing"""
        # Create mock cache files in /tmp
        import os
        cache_files = [
            "/tmp/cpc_secrets_cache",
            "/tmp/cpc_env_cache.sh", 
            "/tmp/cpc_status_cache_test"
        ]
        for cache_file in cache_files:
            os.makedirs(os.path.dirname(cache_file), exist_ok=True)
            with open(cache_file, 'w') as f:
                f.write("mock cache")
        
        result = run_bash_command("core_clear_cache", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Cache cleared successfully" in result.stdout
        
        # Verify cache files were removed
        for cache_file in cache_files:
            assert not Path(cache_file).exists()


class TestCoreListWorkspaces:
    """Test core_list_workspaces() - List Workspaces"""
    
    def test_core_list_workspaces_help_success(self, temp_repo, mock_env):
        """Test help output"""
        result = run_bash_command("core_list_workspaces --help", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Usage: cpc list-workspaces" in result.stdout

    def test_core_list_workspaces_success(self, temp_repo, mock_env):
        """Test successful workspace listing"""
        # Create mock env file
        env_file = temp_repo / "envs" / "test.env"
        env_file.parent.mkdir(parents=True, exist_ok=True)
        env_file.write_text("mock env")
        
        result = run_bash_command("core_list_workspaces", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "Available Workspaces" in result.stdout


class TestCpcSetup:
    """Test cpc_setup() - Setup CPC Project"""
    
    def test_cpc_setup_success(self, temp_repo, mock_env):
        """Test successful CPC project setup"""
        result = run_bash_command("cpc_setup", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "CPC project setup completed" in result.stdout


class TestGetTerraformOutputsJson:
    """Test _get_terraform_outputs_json() - Get Terraform Outputs"""
    
    def test_get_terraform_outputs_json_success(self, temp_repo, mock_env, monkeypatch):
        """Test successful terraform output retrieval"""
        # Mock tofu command
        def mock_tofu(*args, **kwargs):
            return subprocess.CompletedProcess(args=['tofu'], returncode=0, stdout='{"value": {"test": "data"}}')
        
        monkeypatch.setattr(subprocess, 'run', mock_tofu)
        
        result = run_bash_command("_get_terraform_outputs_json test_output", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert '{"test": "data"}' in result.stdout

    def test_get_terraform_outputs_json_error(self, temp_repo, mock_env, monkeypatch):
        """Test error when terraform output fails"""
        # Mock tofu command to fail
        def mock_tofu(*args, **kwargs):
            return subprocess.CompletedProcess(args=['tofu'], returncode=1, stdout='')
        
        monkeypatch.setattr(subprocess, 'run', mock_tofu)
        
        result = run_bash_command("_get_terraform_outputs_json test_output", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Failed to get terraform output" in result.stderr


class TestGetHostnameByIp:
    """Test _get_hostname_by_ip() - Get Hostname by IP"""
    
    def test_get_hostname_by_ip_success(self, temp_repo, mock_env, monkeypatch):
        """Test successful hostname lookup"""
        # Mock terraform output
        def mock_tofu(*args, **kwargs):
            return subprocess.CompletedProcess(args=['tofu'], returncode=0, stdout='{"value": {"node1": {"IP": "10.0.0.1", "hostname": "test-host"}}}')
        
        monkeypatch.setattr(subprocess, 'run', mock_tofu)
        
        result = run_bash_command("_get_hostname_by_ip 10.0.0.1", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        assert "test-host" in result.stdout

    def test_get_hostname_by_ip_not_found_error(self, temp_repo, mock_env, monkeypatch):
        """Test error when IP not found"""
        # Mock terraform output with no matching IP
        def mock_tofu(*args, **kwargs):
            return subprocess.CompletedProcess(args=['tofu'], returncode=0, stdout='{"value": {}}')
        
        monkeypatch.setattr(subprocess, 'run', mock_tofu)
        
        result = run_bash_command("_get_hostname_by_ip 10.0.0.1", env=mock_env, cwd=temp_repo)
        assert result.returncode != 0
        assert "Hostname not found" in result.stderr


class TestAnsibleCreateTempInventory:
    """Test ansible_create_temp_inventory() - Create Temp Inventory"""
    
    def test_ansible_create_temp_inventory_success(self, temp_repo, mock_env):
        """Test successful inventory creation"""
        json_data = '{"node1": {"IP": "10.0.0.1", "hostname": "test-host"}}'
        result = run_bash_command(f"ansible_create_temp_inventory '{json_data}'", env=mock_env, cwd=temp_repo)
        assert result.returncode == 0
        
        # Check if temp file was created and has content
        temp_file_path = result.stdout.strip()
        if temp_file_path and Path(temp_file_path).exists():
            content = Path(temp_file_path).read_text()
            assert "[control_plane]" in content or "[workers]" in content
