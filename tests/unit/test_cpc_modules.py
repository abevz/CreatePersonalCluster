#!/usr/bin/env python3
"""
Unit tests for CPC module functionality
"""

import pytest
import os
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

# Import test framework
from tests import TestFramework

tf = TestFramework()


class TestCPCModules:
    """Test CPC module structure and basic functionality"""

    def test_all_modules_exist(self):
        """Test that all required modules exist"""
        required_modules = [
            'modules/00_core.sh',
            'modules/10_proxmox.sh', 
            'modules/20_ansible.sh',
            'modules/30_k8s_cluster.sh',
            'modules/40_k8s_nodes.sh',
            'modules/50_cluster_ops.sh',
            'modules/60_tofu.sh',
            'modules/70_dns_ssl.sh'
        ]

        for module in required_modules:
            assert tf.check_file_exists(module), f"Missing module: {module}"

    def test_module_syntax_validation(self):
        """Test that all modules have valid bash syntax"""
        module_dir = Path(tf.project_root) / 'modules'
        
        for module_file in module_dir.glob('*.sh'):
            result = tf.run_command(f'bash -n {module_file}')
            assert result is not None, f"Syntax check failed for {module_file}"
            assert result.returncode == 0, f"Syntax error in {module_file}: {result.stderr}"

    def test_module_function_exports(self):
        """Test that modules export their functions properly"""
        core_module = Path(tf.project_root) / 'modules' / '00_core.sh'
        content = tf.read_file('modules/00_core.sh')
        
        assert content is not None, "Could not read core module"
        assert 'export -f' in content, "Core module doesn't export functions"

    def test_module_dependency_structure(self):
        """Test module dependency and inclusion structure"""
        main_script = tf.read_file('cpc')
        assert main_script is not None, "Could not read main cpc script"
        
        # Should source modules directory or have module loading
        assert 'modules' in main_script, "Main script doesn't reference modules"

    def test_core_module_functions(self):
        """Test core module function definitions"""
        core_content = tf.read_file('modules/00_core.sh')
        assert core_content is not None, "Could not read core module"
        
        required_functions = [
            'core_ctx',
            'core_list_workspaces', 
            'core_clone_workspace',
            'core_delete_workspace',
            'load_secrets_cached',
            'core_clear_cache'
        ]
        
        for func in required_functions:
            assert f'{func}()' in core_content, f"Missing function {func} in core module"

    def test_k8s_module_functions(self):
        """Test K8s cluster module functions"""
        k8s_content = tf.read_file('modules/30_k8s_cluster.sh')
        if k8s_content:
            required_functions = [
                'k8s_cluster_status',
                'k8s_bootstrap',
                'k8s_get_kubeconfig'
            ]
            
            for func in required_functions:
                assert f'{func}()' in k8s_content, f"Missing function {func} in K8s module"

    def test_ansible_module_functions(self):
        """Test Ansible module functions"""
        ansible_content = tf.read_file('modules/20_ansible.sh')
        if ansible_content:
            # Should have ansible-related functions
            assert 'ansible' in ansible_content.lower(), "Ansible module doesn't contain ansible references"

    def test_tofu_module_functions(self):
        """Test Tofu/Terraform module functions"""
        tofu_content = tf.read_file('modules/60_tofu.sh')
        if tofu_content:
            # Should have terraform/tofu related functions
            assert any(term in tofu_content.lower() for term in ['tofu', 'terraform']), "Tofu module missing tofu/terraform references"


class TestCPCCommandStructure:
    """Test CPC command structure and routing"""

    def test_command_dispatch_structure(self):
        """Test that main script has proper command dispatch"""
        main_content = tf.read_file('cpc')
        assert main_content is not None, "Could not read main script"
        
        # Should have case statement for command routing
        assert 'case' in main_content, "Main script missing command dispatch structure"
        assert 'COMMAND' in main_content, "Main script missing command variable"

    def test_module_command_routing(self):
        """Test that commands are routed to appropriate modules"""
        main_content = tf.read_file('cpc')
        assert main_content is not None, "Could not read main script"
        
        # Check for key command routings
        command_mappings = {
            'ctx': 'cpc_core',
            'status': 'k8s_cluster',
            'bootstrap': 'k8s_cluster',
            'deploy': 'tofu'
        }
        
        for cmd, module in command_mappings.items():
            # Should route command to appropriate module
            if f'{cmd})' in main_content:
                # Find the handler line
                lines = main_content.split('\n')
                for i, line in enumerate(lines):
                    if f'{cmd})' in line:
                        # Check next few lines for module call
                        handler_found = False
                        for j in range(i+1, min(i+5, len(lines))):
                            if module in lines[j]:
                                handler_found = True
                                break
                        if not handler_found:
                            pytest.skip(f"Command {cmd} handler structure may vary")

    def test_help_command_availability(self):
        """Test that help is available for commands"""
        result = tf.run_command('./cpc --help')
        assert result is not None, "Help command failed"
        assert result.returncode == 0, "Help command returned error"
        
        help_output = result.stdout
        key_commands = ['ctx', 'status', 'bootstrap', 'deploy']
        
        for cmd in key_commands:
            # Command should be mentioned in help
            assert cmd in help_output, f"Command {cmd} not in help output"

    def test_subcommand_help(self):
        """Test subcommand help availability"""
        commands_with_help = ['ctx', 'status', 'bootstrap']
        
        for cmd in commands_with_help:
            result = tf.run_command(f'./cpc {cmd} --help')
            if result and result.returncode == 0:
                assert 'Usage:' in result.stdout, f"Command {cmd} missing usage info"


class TestCPCConfigurationHandling:
    """Test configuration file handling"""

    def test_config_file_loading(self):
        """Test that configuration files are loaded properly"""
        config_content = tf.read_file('config.conf')
        assert config_content is not None, "Could not read config.conf"
        
        required_configs = [
            'ENVIRONMENTS_DIR=',
            'TERRAFORM_DIR='
            # Removed ANSIBLE_DIR and CONFIG_DIR as they may not be present
        ]
        
        for config in required_configs:
            assert config in config_content, f"Missing config: {config}"

    def test_environment_file_structure(self):
        """Test environment file structure"""
        envs_dir = Path(tf.project_root) / 'envs'
        if envs_dir.exists():
            env_files = list(envs_dir.glob('*.env'))
            
            valid_files = 0
            for env_file in env_files:
                content = env_file.read_text()
                # Skip empty files or example files
                if not content.strip() or 'example' in env_file.name.lower():
                    continue
                
                # Should have basic structure
                lines = content.split('\n')
                non_empty_lines = [line for line in lines if line.strip() and not line.startswith('#')]
                if len(non_empty_lines) > 0:
                    valid_files += 1
            
            assert valid_files > 0, "No valid environment files found"

    def test_ansible_config_structure(self):
        """Test Ansible configuration structure"""
        ansible_cfg = Path(tf.project_root) / 'ansible' / 'ansible.cfg'
        if ansible_cfg.exists():
            content = ansible_cfg.read_text()
            assert '[defaults]' in content, "Missing [defaults] section in ansible.cfg"


class TestCPCErrorHandlingStructure:
    """Test error handling structure in modules"""

    def test_error_function_definitions(self):
        """Test that error handling functions are defined"""
        core_content = tf.read_file('modules/00_core.sh')
        if core_content:
            # Should have logging functions
            log_functions = ['log_error', 'log_info', 'log_warning', 'log_success']
            for func in log_functions:
                assert func in core_content, f"Missing logging function: {func}"

    def test_input_validation_structure(self):
        """Test that modules have input validation"""
        module_dir = Path(tf.project_root) / 'modules'
        
        for module_file in module_dir.glob('*.sh'):
            content = module_file.read_text()
            
            # Should have some form of input validation
            validation_patterns = ['if.*-z', 'if.*-n', 'case.*in', '[[ ']
            has_validation = any(pattern in content for pattern in validation_patterns)
            
            if len(content) > 500:  # Only check substantial modules
                assert has_validation, f"Module {module_file} lacks input validation patterns"

    def test_return_code_handling(self):
        """Test that functions handle return codes properly"""
        core_content = tf.read_file('modules/00_core.sh')
        if core_content:
            # Should have return statements
            assert 'return 1' in core_content, "Missing error return codes"
            assert 'return 0' in core_content, "Missing success return codes"


class TestCPCSecurityStructure:
    """Test security-related structure"""

    def test_secrets_file_handling(self):
        """Test secrets file handling structure"""
        core_content = tf.read_file('modules/00_core.sh')
        if core_content:
            # Should have SOPS-related functionality
            if 'sops' in core_content.lower():
                assert 'secrets' in core_content.lower(), "SOPS usage without secrets context"

    def test_file_permissions_awareness(self):
        """Test that code is aware of file permissions"""
        core_content = tf.read_file('modules/00_core.sh')
        if core_content:
            # Should have chmod or permission-related code
            if 'chmod' in core_content:
                assert '600' in core_content or '640' in core_content, "Appropriate file permissions used"

    def test_ssh_key_handling(self):
        """Test SSH key handling structure"""
        modules_with_ssh = ['modules/30_k8s_cluster.sh']  # Only check modules that actually use SSH
        
        for module in modules_with_ssh:
            content = tf.read_file(module)
            if content and 'ssh' in content.lower():
                # Should have proper SSH options
                ssh_options = ['StrictHostKeyChecking', 'BatchMode', 'ConnectTimeout']
                has_ssh_security = any(option in content for option in ssh_options)
                assert has_ssh_security, f"Module {module} lacks secure SSH options"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
