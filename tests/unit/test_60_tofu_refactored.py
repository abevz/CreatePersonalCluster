#!/usr/bin/env python3
"""
Unit tests for refactored functions in modules/60_tofu.sh
"""

import pytest
import subprocess
import tempfile
import os
from pathlib import Path


class TestRefactoredTofuFunctions:
    """Test refactored functions from modules/60_tofu.sh"""

    def setup_method(self):
        """Setup for each test method"""
        self.project_root = Path(__file__).parent.parent.parent
        self.module_path = self.project_root / "modules" / "60_tofu.sh"
        self.core_module_path = self.project_root / "modules" / "00_core.sh"
        self.config_path = self.project_root / "config.conf"

    def run_bash_command(self, command, cwd=None, env=None):
        """Helper to run bash commands with proper sourcing"""
        full_command = f"""
        source {self.config_path}
        source {self.core_module_path}
        source {self.module_path}
        {command}
        """
        return subprocess.run(
            ['bash', '-c', full_command],
            cwd=cwd or self.project_root,
            env=env,
            capture_output=True,
            text=True
        )

    def test_cpc_tofu_dispatcher_success(self):
        """Test cpc_tofu dispatcher with valid command"""
        result = self.run_bash_command("cpc_tofu deploy --help")
        assert result.returncode == 0
        assert "Usage: cpc deploy" in result.stdout

    def test_cpc_tofu_dispatcher_error(self):
        """Test cpc_tofu dispatcher with invalid command"""
        result = self.run_bash_command("cpc_tofu invalid-command")
        assert result.returncode != 0
        assert "Unknown tofu command" in result.stderr

    def test_tofu_deploy_help_success(self):
        """Test tofu_deploy help output"""
        result = self.run_bash_command("tofu_deploy --help")
        assert result.returncode == 0
        assert "Usage: cpc deploy" in result.stdout

    def test_tofu_deploy_error_no_context(self):
        """Test tofu_deploy with missing context"""
        # Mock missing context
        env = os.environ.copy()
        env['CPC_WORKSPACE'] = ''
        result = self.run_bash_command("tofu_deploy plan", env=env)
        assert result.returncode != 0
        assert "Failed to get current cluster context" in result.stderr

    def test_tofu_start_vms_help_success(self):
        """Test tofu_start_vms help output"""
        result = self.run_bash_command("tofu_start_vms --help")
        assert result.returncode == 0
        assert "Usage: cpc start-vms" in result.stdout

    def test_tofu_start_vms_error_no_context(self):
        """Test tofu_start_vms with missing context"""
        env = os.environ.copy()
        env['CPC_WORKSPACE'] = ''
        result = self.run_bash_command("tofu_start_vms", env=env)
        assert result.returncode != 0
        assert "Failed to get current cluster context" in result.stderr

    def test_tofu_stop_vms_help_success(self):
        """Test tofu_stop_vms help output"""
        result = self.run_bash_command("tofu_stop_vms --help")
        assert result.returncode == 0
        assert "Usage: cpc stop-vms" in result.stdout

    def test_tofu_stop_vms_error_no_context(self):
        """Test tofu_stop_vms with missing context"""
        env = os.environ.copy()
        env['CPC_WORKSPACE'] = ''
        result = self.run_bash_command("tofu_stop_vms", env=env)
        assert result.returncode != 0
        assert "Failed to get current cluster context" in result.stderr

    def test_tofu_generate_hostnames_success(self):
        """Test tofu_generate_hostnames with valid setup"""
        # Create a mock script for testing
        with tempfile.TemporaryDirectory() as temp_dir:
            mock_script = Path(temp_dir) / "generate_node_hostnames.sh"
            mock_script.write_text("#!/bin/bash\necho 'Mock hostname generation'")
            mock_script.chmod(0o755)

            env = os.environ.copy()
            env['REPO_PATH'] = temp_dir
            env['CPC_WORKSPACE'] = 'test'

            result = self.run_bash_command("tofu_generate_hostnames", env=env)
            assert result.returncode == 0
            assert "Hostname configurations generated successfully" in result.stdout

    def test_tofu_generate_hostnames_error_no_workspace(self):
        """Test tofu_generate_hostnames with missing workspace"""
        env = os.environ.copy()
        env['CPC_WORKSPACE'] = ''
        result = self.run_bash_command("tofu_generate_hostnames", env=env)
        assert result.returncode != 0
        assert "CPC_WORKSPACE environment variable not set" in result.stderr

    def test_tofu_show_cluster_info_help_success(self):
        """Test tofu_show_cluster_info help output"""
        result = self.run_bash_command("tofu_show_cluster_info --help")
        assert result.returncode == 0
        assert "Usage: cpc cluster-info" in result.stdout

    def test_tofu_show_cluster_info_error_invalid_format(self):
        """Test tofu_show_cluster_info with invalid format"""
        result = self.run_bash_command("tofu_show_cluster_info --format invalid")
        assert result.returncode != 0
        assert "Invalid format" in result.stderr

    def test_tofu_load_workspace_env_vars_success(self):
        """Test tofu_load_workspace_env_vars with valid env file"""
        with tempfile.TemporaryDirectory() as temp_dir:
            env_file = Path(temp_dir) / "test.env"
            env_file.write_text("RELEASE_LETTER=a\nADDITIONAL_WORKERS=2\n")

            env = os.environ.copy()
            env['REPO_PATH'] = temp_dir

            result = self.run_bash_command("tofu_load_workspace_env_vars test", env=env)
            assert result.returncode == 0
            # Check if variables are set (this might require checking exported vars)

    def test_tofu_load_workspace_env_vars_error_no_file(self):
        """Test tofu_load_workspace_env_vars with missing env file"""
        with tempfile.TemporaryDirectory() as temp_dir:
            env = os.environ.copy()
            env['REPO_PATH'] = temp_dir

            result = self.run_bash_command("tofu_load_workspace_env_vars nonexistent", env=env)
            assert result.returncode == 0  # Should not fail, just log debug

    def test_tofu_update_node_info_success(self):
        """Test tofu_update_node_info with valid JSON"""
        json_data = '{"node1": {"IP": "10.0.0.1", "hostname": "node1", "VM_ID": "100"}}'
        result = self.run_bash_command(f"tofu_update_node_info '{json_data}'")
        assert result.returncode == 0
        assert "Successfully parsed 1 nodes" in result.stdout

    def test_tofu_update_node_info_error_invalid_json(self):
        """Test tofu_update_node_info with invalid JSON"""
        result = self.run_bash_command("tofu_update_node_info 'invalid json'")
        assert result.returncode != 0
        assert "Failed to parse node names" in result.stderr

    def test_tofu_cluster_info_help_success(self):
        """Test tofu_cluster_info_help output"""
        result = self.run_bash_command("tofu_cluster_info_help")
        assert result.returncode == 0
        assert "Usage: cpc cluster-info" in result.stdout