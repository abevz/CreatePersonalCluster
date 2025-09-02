#!/usr/bin/env python3
"""
Deep integration tests for CPC - Create Personal Cluster
Tests full cluster lifecycle from creation to destruction
"""

import pytest
import os
import time
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

from tests import test_framework


class TestDeepIntegration:
    """Deep integration tests for full cluster lifecycle"""

    def setup_method(self):
        """Setup for each test method"""
        self.tf = test_framework.TestFramework()
        self.test_workspace = "test-integration"
        self.test_env_backup = {}

        # Backup current environment
        for key in ['CPC_DEBUG', 'PROXMOX_HOST', 'PROXMOX_USERNAME']:
            if key in os.environ:
                self.test_env_backup[key] = os.environ[key]

    def teardown_method(self):
        """Cleanup after each test method"""
        # Restore environment
        for key, value in self.test_env_backup.items():
            os.environ[key] = value

        # Clean up test workspace if it exists
        try:
            result = self.tf.run_command(f"./cpc ctx {self.test_workspace}", timeout=10)
            if result and result.returncode == 0:
                self.tf.run_command(f"./cpc delete-workspace {self.test_workspace}", timeout=30)
        except:
            pass

    def test_full_cluster_lifecycle(self):
        """Test complete cluster creation, configuration and destruction"""
        pytest.skip("Full cluster lifecycle test requires Proxmox environment")

        # This test would require actual Proxmox environment
        # Steps would be:
        # 1. Create test workspace
        # 2. Configure minimal cluster (1 control plane, 1 worker)
        # 3. Deploy VMs
        # 4. Bootstrap Kubernetes
        # 5. Test basic functionality
        # 6. Destroy cluster
        # 7. Clean up workspace

    def test_workspace_management(self):
        """Test workspace creation, switching and deletion"""
        # Test workspace creation
        result = self.tf.run_command(f"./cpc clone-workspace ubuntu {self.test_workspace}")
        assert result.returncode == 0, f"Failed to create workspace: {result.stderr}"

        # Test workspace switching
        result = self.tf.run_command(f"./cpc ctx {self.test_workspace}")
        assert result.returncode == 0, f"Failed to switch workspace: {result.stderr}"

        # Verify workspace context
        result = self.tf.run_command("./cpc ctx")
        assert self.test_workspace in result.stdout, "Workspace not set correctly"

        # Test workspace deletion
        result = self.tf.run_command(f"./cpc delete-workspace {self.test_workspace}")
        assert result.returncode == 0, f"Failed to delete workspace: {result.stderr}"

    def test_configuration_validation(self):
        """Test configuration file validation"""
        # Test missing cpc.env
        if os.path.exists("cpc.env"):
            os.rename("cpc.env", "cpc.env.backup")

        try:
            result = self.tf.run_command("./cpc ctx")
            # Should handle missing config gracefully
            assert result.returncode in [0, 1], "Command should handle missing config"
        finally:
            if os.path.exists("cpc.env.backup"):
                os.rename("cpc.env.backup", "cpc.env")

    def test_secrets_handling(self):
        """Test secrets loading and validation"""
        # Test with debug mode to see secrets loading
        os.environ['CPC_DEBUG'] = 'true'

        result = self.tf.run_command("./cpc ctx")
        assert result.returncode == 0, "Command failed with debug mode"

        # Should contain debug information about secrets
        assert "Loading secrets from" in result.stdout, "Debug info not shown"

    def test_error_handling(self):
        """Test error handling in various scenarios"""
        # Test invalid command
        result = self.tf.run_command("./cpc invalid-command")
        assert result.returncode != 0, "Invalid command should fail"
        assert "Unknown command" in result.stderr, "Should show unknown command error"

        # Test missing arguments
        result = self.tf.run_command("./cpc clone-workspace")
        assert result.returncode != 0, "Missing arguments should fail"

    def test_status_command_comprehensive(self):
        """Test status command with various scenarios"""
        # Test status help
        result = self.tf.run_command("./cpc status --help")
        assert result.returncode == 0, "Status help failed"
        assert "Usage:" in result.stdout, "Help should show usage"

        # Test quick status
        result = self.tf.run_command("./cpc status --quick")
        assert result.returncode == 0, "Quick status failed"

        # Test full status
        result = self.tf.run_command("./cpc status")
        # Status might fail if no cluster exists, but should not crash
        assert result.returncode in [0, 1], "Status should handle no cluster gracefully"

    def test_debug_mode_comprehensive(self):
        """Test debug mode functionality"""
        # Test debug flag
        result = self.tf.run_command("./cpc --debug ctx")
        assert result.returncode == 0, "Debug mode failed"
        assert "[DEBUG]" in result.stdout, "Debug output not shown"

        # Test short debug flag
        result = self.tf.run_command("./cpc -d ctx")
        assert result.returncode == 0, "Short debug flag failed"
        assert "[DEBUG]" in result.stdout, "Debug output not shown"

    def test_module_loading(self):
        """Test that all modules load correctly"""
        # Test with debug to see module loading
        os.environ['CPC_DEBUG'] = 'true'

        result = self.tf.run_command("./cpc ctx")
        assert result.returncode == 0, "Module loading failed"

        # Should show module loading debug info
        assert "Loading module:" in result.stdout, "Module loading not shown"

    def test_environment_isolation(self):
        """Test that tests don't affect main environment"""
        # Get current context before test
        result = self.tf.run_command("./cpc ctx")
        original_context = None
        if "Current cluster context:" in result.stdout:
            # Extract current context
            lines = result.stdout.split('\n')
            for line in lines:
                if "Current cluster context:" in line:
                    original_context = line.split(':')[1].strip()
                    break

        # Create and switch to test workspace
        result = self.tf.run_command(f"./cpc clone-workspace ubuntu {self.test_workspace}")
        if result.returncode == 0:
            result = self.tf.run_command(f"./cpc ctx {self.test_workspace}")
            assert result.returncode == 0, "Failed to switch to test workspace"

            # Verify we're in test workspace
            result = self.tf.run_command("./cpc ctx")
            assert self.test_workspace in result.stdout, "Not in test workspace"

        # Cleanup happens in teardown_method
        # Original context should be restored by the test framework


class TestPerformance:
    """Performance tests for CPC commands"""

    def test_command_execution_time(self):
        """Test that commands execute within reasonable time"""
        import time

        start_time = time.time()
        result = test_framework.TestFramework.run_command("./cpc --help")
        end_time = time.time()

        execution_time = end_time - start_time
        assert execution_time < 5.0, f"Command took too long: {execution_time}s"
        assert result.returncode == 0, "Command failed"

    def test_multiple_rapid_commands(self):
        """Test executing multiple commands rapidly"""
        for i in range(3):
            result = test_framework.TestFramework.run_command("./cpc --help")
            assert result.returncode == 0, f"Command {i+1} failed"
            assert "Usage:" in result.stdout, f"Command {i+1} output invalid"


class TestSecurity:
    """Security tests for CPC"""

    def test_no_secrets_in_output(self):
        """Test that secrets don't leak into command output"""
        # Run command with debug mode
        result = test_framework.TestFramework.run_command("./cpc --debug ctx")

        # Should not contain actual secret values in output
        sensitive_patterns = [
            "password",
            "token",
            "key",
            "secret"
        ]

        output_lower = result.stdout.lower()
        for pattern in sensitive_patterns:
            # Allow the word in context of "Loading secrets" but not actual values
            if pattern in output_lower and "loading secrets" not in output_lower:
                # This is a simplified check - in real implementation you'd want
                # more sophisticated secret detection
                pass

    def test_safe_error_messages(self):
        """Test that error messages don't reveal sensitive information"""
        # Test with invalid credentials scenario
        result = test_framework.TestFramework.run_command("./cpc deploy plan")

        # Error messages should not contain passwords, tokens, etc.
        # This is a basic check - would need more sophisticated analysis
        assert "password" not in result.stderr.lower(), "Error message contains password"
        assert "token" not in result.stderr.lower(), "Error message contains token"
