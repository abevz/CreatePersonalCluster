#!/usr/bin/env python3
"""
Unit tests for core CPC functions
"""

import pytest
import os
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

# Import test framework
from tests import test_framework


class TestCoreFunctions:
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
            'ansible/ansible.cfg',
            'terraform/main.tf'
        ]

        for filepath in required_files:
            assert test_framework.check_file_exists(filepath), f"Missing required file: {filepath}"

    def test_cpc_script_executable(self):
        """Test that main CPC script is executable"""
        cpc_path = Path(test_framework.project_root) / 'cpc'
        assert cpc_path.exists(), "CPC script not found"
        assert os.access(cpc_path, os.X_OK), "CPC script is not executable"

    def test_cpc_help_output(self):
        """Test CPC help command output"""
        result = test_framework.run_command('./cpc --help')
        assert result is not None, "CPC help command failed"
        assert result.returncode == 0, f"CPC help failed with code {result.returncode}"
        assert 'Usage:' in result.stdout, "Help output doesn't contain usage information"
        assert 'Commands:' in result.stdout, "Help output doesn't contain commands section"

    def test_module_files_syntax(self):
        """Test that all module files have valid bash syntax"""
        modules_dir = Path(test_framework.project_root) / 'modules'
        for module_file in modules_dir.glob('*.sh'):
            # Use bash -n to check syntax
            result = test_framework.run_command(f'bash -n {module_file}')
            assert result.returncode == 0, f"Syntax error in {module_file}: {result.stderr}"

    @pytest.mark.parametrize("module_file", [
        'modules/00_core.sh',
        'modules/20_ansible.sh',
        'modules/30_k8s_cluster.sh',
        'modules/40_k8s_nodes.sh',
        'modules/50_cluster_ops.sh',
        'modules/60_tofu.sh',
        'modules/80_ssh.sh'
    ])
    def test_module_has_shebang(self, module_file):
        """Test that all modules have proper shebang"""
        content = test_framework.read_file(module_file)
        assert content is not None, f"Could not read {module_file}"
        assert content.startswith('#!/bin/bash'), f"{module_file} missing proper shebang"

    def test_env_example_exists(self):
        """Test that environment example file exists"""
        assert test_framework.check_file_exists('cpc.env.example'), "cpc.env.example not found"

    def test_readme_has_required_sections(self):
        """Test that README has required sections"""
        readme_content = test_framework.read_file('README.md')
        assert readme_content is not None, "README.md not found"

        required_sections = [
            '# 🚀 Create Personal Cluster',
            '## 🎯 Overview',
            '## ✨ Key Features',
            '## 🚀 Quick Start',
            '## 📖 Documentation',
            '## 🛠️ Installation'
        ]

        for section in required_sections:
            assert section in readme_content, f"README missing section: {section}"


class TestConfigurationValidation:
    """Test configuration file validation"""

    def test_env_example_has_required_vars(self):
        """Test that cpc.env.example has required variables"""
        content = test_framework.read_file('cpc.env.example')
        assert content is not None, "cpc.env.example not found"

        required_vars = [
            'NETWORK_CIDR',
            'NETWORK_GATEWAY',
            'STATIC_IP_START',
            'WORKSPACE_IP_BLOCK_SIZE'
        ]

        for var in required_vars:
            assert var in content, f"cpc.env.example missing variable: {var}"

    def test_terraform_config_valid(self):
        """Test that Terraform configuration is valid"""
        # This would require terraform to be installed
        # For now, just check that files exist
        tf_files = ['terraform/main.tf', 'terraform/variables.tf', 'terraform/outputs.tf']
        for tf_file in tf_files:
            assert test_framework.check_file_exists(tf_file), f"Missing Terraform file: {tf_file}"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
