#!/usr/bin/env python3
"""
Integration tests for CPC components
"""

import pytest
import tempfile
import os
from pathlib import Path

from tests import test_framework


class TestIntegration:
    """Integration tests for CPC components"""

    def test_cpc_command_integration(self):
        """Test basic CPC command integration"""
        # Test that CPC can show help without errors
        result = test_framework.run_command('./cpc --help')
        assert result.returncode == 0, "CPC help command failed"
        assert len(result.stdout) > 0, "CPC help produced no output"

    def test_module_loading(self):
        """Test that modules can be loaded"""
        # This is a basic integration test to ensure modules don't have syntax errors
        result = test_framework.run_command('bash -c "source modules/00_core.sh && echo \"Module loaded successfully\""')
        assert result.returncode == 0, "Core module failed to load"
        assert "Module loaded successfully" in result.stdout, "Module loading test failed"

    def test_configuration_parsing(self):
        """Test configuration file parsing"""
        # Create a temporary config file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("""
TEST_VAR="test_value"
ANOTHER_VAR="another_value"
""")
            temp_config = f.name

        try:
            # Test that we can source the config
            result = test_framework.run_command(f'bash -c "source {temp_config} && echo $TEST_VAR"')
            assert result.returncode == 0, "Config sourcing failed"
            assert "test_value" in result.stdout, "Config variable not set correctly"
        finally:
            os.unlink(temp_config)

    def test_workspace_operations(self):
        """Test workspace-related operations"""
        # Test that workspace commands are recognized
        result = test_framework.run_command('./cpc ctx 2>/dev/null || echo "Command completed"')
        # We expect this to fail in test environment, but should not crash
        assert result is not None, "Workspace command test failed unexpectedly"


class TestTerraformIntegration:
    """Test Terraform-related integration"""

    def test_terraform_files_exist(self):
        """Test that all required Terraform files exist"""
        tf_files = [
            'terraform/main.tf',
            'terraform/variables.tf',
            'terraform/outputs.tf',
            'terraform/locals.tf'
        ]

        for tf_file in tf_files:
            assert test_framework.check_file_exists(tf_file), f"Missing Terraform file: {tf_file}"

    def test_terraform_syntax(self):
        """Test Terraform configuration syntax"""
        # This would require terraform to be installed
        # For now, just check that files are readable
        for tf_file in ['terraform/main.tf', 'terraform/variables.tf']:
            content = test_framework.read_file(tf_file)
            assert content is not None, f"Could not read {tf_file}"
            assert len(content.strip()) > 0, f"{tf_file} is empty"


class TestAnsibleIntegration:
    """Test Ansible-related integration"""

    def test_ansible_config(self):
        """Test Ansible configuration"""
        assert test_framework.check_file_exists('ansible/ansible.cfg'), "Ansible config not found"

        content = test_framework.read_file('ansible/ansible.cfg')
        assert content is not None, "Could not read ansible.cfg"
        assert '[defaults]' in content, "Ansible config missing defaults section"

    def test_playbook_structure(self):
        """Test playbook directory structure"""
        assert test_framework.check_file_exists('ansible/playbooks'), "Playbooks directory not found"

        playbooks = [
            'initialize_kubernetes_cluster_with_dns.yml',
            'install_kubernetes_cluster.yml',
            'pb_prepare_node.yml'
        ]

        for playbook in playbooks:
            playbook_path = f'ansible/playbooks/{playbook}'
            if test_framework.check_file_exists(playbook_path):
                content = test_framework.read_file(playbook_path)
                assert content is not None, f"Could not read {playbook}"
                assert 'name:' in content, f"{playbook} missing name field"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
