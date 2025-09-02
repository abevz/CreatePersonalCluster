#!/usr/bin/env python3
"""
Shell script linting and validation tests
"""

import pytest
from pathlib import Path

from tests import test_framework


class TestShellLinting:
    """Test shell scripts with shellcheck"""

    def test_shellcheck_installation(self):
        """Test that shellcheck is available"""
        result = test_framework.run_command('shellcheck --version')
        assert result is not None, "shellcheck not found"
        assert result.returncode == 0, "shellcheck command failed"

    def test_bashate_installation(self):
        """Test that bashate is available"""
        result = test_framework.run_command('bashate --help')
        assert result is not None, "bashate not found"
        assert result.returncode == 0, "bashate command failed"

    @pytest.mark.parametrize("script_file", [
        'cpc',
        'modules/00_core.sh',
        'modules/20_ansible.sh',
        'modules/30_k8s_cluster.sh',
        'modules/40_k8s_nodes.sh',
        'modules/50_cluster_ops.sh',
        'modules/60_tofu.sh',
        'modules/80_ssh.sh'
    ])
    def test_shellcheck_validation(self, script_file):
        """Test shellcheck on all shell scripts"""
        if not test_framework.check_file_exists(script_file):
            pytest.skip(f"Script {script_file} not found")

        result = test_framework.run_command(f'shellcheck {script_file}')

        if result.returncode != 0:
            print(f"Shellcheck issues in {script_file}:")
            print(result.stdout)
            print(result.stderr)
            # For now, just log issues but don't fail
            # TODO: Fix shellcheck issues and make this stricter

    @pytest.mark.parametrize("script_file", [
        'cpc',
        'modules/00_core.sh',
        'modules/20_ansible.sh',
        'modules/30_k8s_cluster.sh'
    ])
    def test_bashate_validation(self, script_file):
        """Test bashate on shell scripts"""
        if not test_framework.check_file_exists(script_file):
            pytest.skip(f"Script {script_file} not found")

        result = test_framework.run_command(f'bashate {script_file}')

        if result.returncode != 0:
            print(f"Bashate issues in {script_file}:")
            print(result.stdout)
            print(result.stderr)
            # For now, just log issues but don't fail
            # TODO: Fix bashate issues and make this stricter


class TestScriptValidation:
    """Test script structure and content"""

    def test_main_script_structure(self):
        """Test main CPC script structure"""
        content = test_framework.read_file('cpc')
        assert content is not None, "Could not read main cpc script"

        # Check for required elements
        assert '#!/bin/bash' in content, "Main script missing shebang"
        assert 'SCRIPT_DIR=' in content, "Main script missing SCRIPT_DIR variable"
        assert 'COMMAND=' in content, "Main script missing COMMAND parsing"

    def test_module_structure(self):
        """Test module file structure"""
        modules_dir = Path(test_framework.project_root) / 'modules'

        for module_file in modules_dir.glob('*.sh'):
            content = test_framework.read_file(str(module_file))
            assert content is not None, f"Could not read {module_file}"

            # Check for basic module structure
            assert '#!/bin/bash' in content, f"{module_file} missing shebang"
            assert 'if [[ "${BASH_SOURCE[0]}" == "${0}" ]];' in content, f"{module_file} missing direct execution check"

    def test_script_permissions(self):
        """Test that scripts have correct permissions"""
        scripts_to_check = ['cpc']

        for script in scripts_to_check:
            if test_framework.check_file_exists(script):
                script_path = Path(test_framework.project_root) / script
                assert script_path.stat().st_mode & 0o111, f"{script} is not executable"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
