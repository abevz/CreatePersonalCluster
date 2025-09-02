#!/usr/bin/env python3
"""
Comprehensive unit tests for CPC core functions
"""

import pytest
import os
import tempfile
import shutil
from pathlib import Path
from unittest.mock import patch, MagicMock, call
import json

# Import test framework
from tests import TestFramework

tf = TestFramework()


class TestCPCCore:
    """Test core CPC functionality"""

    def test_project_structure(self):
        """Test that project has required structure"""
        required_files = [
            'cpc',
            'cpc.env.example', 
            'README.md',
            'modules/00_core.sh',
            'modules/20_ansible.sh',
            'modules/30_k8s_cluster.sh',
            'modules/40_k8s_nodes.sh',
            'modules/50_cluster_ops.sh',
            'modules/60_tofu.sh',
            'modules/70_dns_ssl.sh',
            'ansible/ansible.cfg',
            'terraform/main.tf',
            'config.conf',
            'pytest.ini'
        ]

        for filepath in required_files:
            assert tf.check_file_exists(filepath), f"Missing required file: {filepath}"

    def test_cpc_script_executable(self):
        """Test that main CPC script is executable"""
        cpc_path = Path(tf.project_root) / 'cpc'
        assert cpc_path.exists(), "CPC script not found"
        assert os.access(cpc_path, os.X_OK), "CPC script is not executable"

    def test_cpc_help_output(self):
        """Test CPC help command output"""
        result = tf.run_command('./cpc --help')
        assert result is not None, "CPC help command failed"
        assert result.returncode == 0, f"CPC help failed with code {result.returncode}"
        assert 'Usage:' in result.stdout, "Help output doesn't contain usage information"
        assert 'Commands:' in result.stdout, "Help output doesn't contain commands section"

    def test_cpc_basic_commands_help(self):
        """Test individual command help"""
        commands = ['ctx', 'list-workspaces', 'status']  # Removed quick-status as it doesn't support --help
        
        for cmd in commands:
            result = tf.run_command(f'./cpc {cmd} --help')
            if result and result.returncode == 0:
                assert 'Usage:' in result.stdout, f"Command {cmd} help missing usage"

    def test_workspace_commands(self):
        """Test workspace-related commands"""
        # Test list-workspaces
        result = tf.run_command('./cpc list-workspaces')
        assert result is not None, "list-workspaces command failed"
        assert result.returncode == 0, f"list-workspaces failed with code {result.returncode}"
        assert 'Available Workspaces:' in result.stdout, "Missing workspace list header"

    def test_current_context_display(self):
        """Test current context display"""
        result = tf.run_command('./cpc ctx')
        assert result is not None, "ctx command failed"
        assert result.returncode == 0, f"ctx failed with code {result.returncode}"
        assert 'Current cluster context:' in result.stdout, "Missing current context info"

    def test_quick_status_command(self):
        """Test quick-status command"""
        result = tf.run_command('./cpc quick-status')
        assert result is not None, "quick-status command failed"
        assert result.returncode == 0, f"quick-status failed with code {result.returncode}"
        assert 'Quick Status' in result.stdout, "Missing quick status header"

    def test_module_files_syntax(self):
        """Test that all module files have valid bash syntax"""
        module_dir = Path(tf.project_root) / 'modules'
        for module_file in module_dir.glob('*.sh'):
            result = tf.run_command(f'bash -n {module_file}')
            assert result is not None, f"Syntax check failed for {module_file}"
            assert result.returncode == 0, f"Syntax error in {module_file}: {result.stderr}"

    def test_configuration_files(self):
        """Test configuration files are valid"""
        config_file = Path(tf.project_root) / 'config.conf'
        assert config_file.exists(), "config.conf not found"
        
        content = tf.read_file('config.conf')
        assert content is not None, "Could not read config.conf"
        assert 'ENVIRONMENTS_DIR=' in content, "Missing ENVIRONMENTS_DIR config"
        assert 'TERRAFORM_DIR=' in content, "Missing TERRAFORM_DIR config"

    def test_ansible_configuration(self):
        """Test Ansible configuration"""
        ansible_cfg = Path(tf.project_root) / 'ansible' / 'ansible.cfg'
        assert ansible_cfg.exists(), "ansible.cfg not found"
        
        content = tf.read_file('ansible/ansible.cfg')
        assert content is not None, "Could not read ansible.cfg"
        assert '[defaults]' in content, "Missing defaults section in ansible.cfg"

    @pytest.mark.slow
    def test_secrets_loading_structure(self):
        """Test secrets loading functionality structure"""
        # Test that secrets-related commands exist
        result = tf.run_command('./cpc load_secrets --help')
        if result and result.returncode == 0:
            assert 'secrets' in result.stdout.lower(), "Missing secrets help info"

    def test_cache_commands(self):
        """Test cache management commands"""
        result = tf.run_command('./cpc clear-cache --help')
        if result and result.returncode == 0:
            assert 'cache' in result.stdout.lower(), "Missing cache help info"

    def test_environment_directory_structure(self):
        """Test environment directory structure"""
        envs_dir = Path(tf.project_root) / 'envs'
        if envs_dir.exists():
            env_files = list(envs_dir.glob('*.env'))
            assert len(env_files) > 0, "No environment files found"
            
            valid_files = 0
            for env_file in env_files:
                content = env_file.read_text()
                # Skip empty files or example files
                if not content.strip() or 'example' in env_file.name.lower():
                    continue
                    
                # Check that file has some configuration
                lines = content.split('\n')
                config_lines = [line for line in lines if '=' in line and not line.startswith('#')]
                if len(config_lines) > 0:
                    valid_files += 1
            
            assert valid_files > 0, "No valid environment files found"

    def test_terraform_structure(self):
        """Test Terraform directory structure"""
        tf_dir = Path(tf.project_root) / 'terraform'
        assert tf_dir.exists(), "Terraform directory not found"
        
        required_tf_files = ['main.tf', 'variables.tf', 'outputs.tf', 'locals.tf']
        for tf_file in required_tf_files:
            tf_path = tf_dir / tf_file
            if tf_path.exists():
                content = tf_path.read_text()
                assert len(content) > 0, f"Empty Terraform file: {tf_file}"

    def test_logs_and_recovery_system(self):
        """Test logging and recovery system"""
        # Test that recovery system initializes
        result = tf.run_command('./cpc quick-status')
        if result and result.returncode == 0:
            assert 'Recovery system initialized' in result.stdout, "Recovery system not initialized"


class TestCPCCaching:
    """Test CPC caching functionality"""

    def test_cache_clear_command(self):
        """Test cache clearing"""
        result = tf.run_command('./cpc clear-cache')
        assert result is not None, "clear-cache command failed"
        # Cache clear should work even if no cache exists
        assert result.returncode == 0, f"clear-cache failed with code {result.returncode}"

    def test_cache_file_patterns(self):
        """Test cache file naming patterns"""
        # Create some dummy cache files to test clearing
        cache_files = [
            '/tmp/cpc_env_cache.sh',
            '/tmp/cpc_status_cache_test',
            '/tmp/cpc_ssh_cache_test'
        ]
        
        for cache_file in cache_files:
            Path(cache_file).touch()
        
        result = tf.run_command('./cpc clear-cache')
        assert result is not None, "Cache clear failed"
        
        # Check that cache files were removed
        for cache_file in cache_files:
            assert not Path(cache_file).exists(), f"Cache file not cleared: {cache_file}"


class TestCPCWorkspaceManagement:
    """Test workspace management functionality"""

    def test_workspace_listing(self):
        """Test workspace listing functionality"""
        result = tf.run_command('./cpc list-workspaces')
        assert result is not None, "list-workspaces failed"
        assert result.returncode == 0, f"list-workspaces failed with code {result.returncode}"
        
        output_lines = result.stdout.split('\n')
        workspace_section_found = False
        for line in output_lines:
            if 'Available Workspaces:' in line:
                workspace_section_found = True
                break
        
        assert workspace_section_found, "Workspace section not found in output"

    def test_context_commands(self):
        """Test context-related commands"""
        # Test getting current context
        result = tf.run_command('./cpc ctx')
        assert result is not None, "ctx command failed"
        assert result.returncode == 0, f"ctx failed with code {result.returncode}"


class TestCPCErrorHandling:
    """Test error handling and validation"""

    def test_invalid_command(self):
        """Test handling of invalid commands"""
        result = tf.run_command('./cpc invalid-command-xyz')
        assert result is not None, "Invalid command test failed"
        assert result.returncode != 0, "Invalid command should return non-zero exit code"

    def test_missing_arguments(self):
        """Test handling of missing required arguments"""
        # Test commands that require arguments
        commands_requiring_args = ['clone-workspace', 'delete-workspace']
        
        for cmd in commands_requiring_args:
            result = tf.run_command(f'./cpc {cmd}')
            if result is not None:
                # Should either return help or error
                assert result.returncode != 0 or 'Usage:' in result.stdout, f"Command {cmd} should handle missing args"

    def test_help_flag_variants(self):
        """Test different help flag variants"""
        help_flags = ['--help', '-h', 'help']
        
        for flag in help_flags:
            result = tf.run_command(f'./cpc {flag}')
            if result and result.returncode == 0:
                assert 'Usage:' in result.stdout, f"Help flag {flag} should show usage"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
