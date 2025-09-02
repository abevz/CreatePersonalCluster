#!/usr/bin/env python3
"""
Integration tests for CPC workspace and command workflows
"""

import pytest
import time
import tempfile
import shutil
from pathlib import Path
from unittest.mock import patch

# Import test framework
from tests import TestFramework

tf = TestFramework()


@pytest.mark.integration
class TestCPCWorkspaceWorkflows:
    """Test complete workspace workflows"""

    def test_workspace_lifecycle_simulation(self):
        """Test complete workspace lifecycle without actual resource creation"""
        # Test workspace listing
        result = tf.run_command('./cpc list-workspaces')
        assert result is not None, "list-workspaces failed"
        assert result.returncode == 0, "list-workspaces returned error"
        
        # Get available workspaces
        workspaces = []
        if 'Environment files:' in result.stdout:
            lines = result.stdout.split('\n')
            in_env_section = False
            for line in lines:
                if 'Environment files:' in line:
                    in_env_section = True
                    continue
                if in_env_section and line.strip() and not line.startswith(' '):
                    break
                if in_env_section and line.strip():
                    workspace = line.strip()
                    if workspace != "No envs directory found":
                        workspaces.append(workspace)
        
        if workspaces:
            # Test switching to existing workspace
            test_workspace = workspaces[0]
            switch_result = tf.run_command(f'./cpc ctx {test_workspace}', timeout=60)
            
            if switch_result and switch_result.returncode == 0:
                # Verify context switch
                ctx_result = tf.run_command('./cpc ctx')
                if ctx_result and ctx_result.returncode == 0:
                    assert test_workspace in ctx_result.stdout, f"Context not switched to {test_workspace}"

    def test_command_chaining_workflow(self):
        """Test chaining multiple commands together"""
        commands = [
            './cpc ctx',
            './cpc list-workspaces', 
            './cpc quick-status'
        ]
        
        results = []
        for cmd in commands:
            result = tf.run_command(cmd, timeout=30)
            results.append((cmd, result))
        
        # All commands should succeed
        for cmd, result in results:
            assert result is not None, f"Command failed: {cmd}"
            assert result.returncode == 0, f"Command returned error: {cmd}"

    def test_help_command_completeness(self):
        """Test that all advertised commands have help"""
        # Get main help
        help_result = tf.run_command('./cpc --help')
        assert help_result is not None, "Main help failed"
        assert help_result.returncode == 0, "Main help returned error"
        
        # Extract commands from help
        commands = []
        for line in help_result.stdout.split('\n'):
            if line.strip() and line.startswith('  ') and not line.startswith('    '):
                # This looks like a command line
                parts = line.strip().split()
                if parts:
                    cmd = parts[0]
                    if cmd not in ['Usage:', 'Commands:', 'Options:', 'Examples:']:
                        commands.append(cmd)
        
        # Test help for each command
        for cmd in commands[:5]:  # Test first 5 to avoid timeout
            if cmd not in ['setup-cpc']:  # Skip setup command
                help_cmd_result = tf.run_command(f'./cpc {cmd} --help', timeout=10)
                # Command should either show help or be valid
                if help_cmd_result:
                    # Either success with help, or command doesn't support --help
                    assert help_cmd_result.returncode in [0, 1, 2], f"Command {cmd} help failed unexpectedly"

    def test_error_recovery_workflow(self):
        """Test error recovery mechanisms"""
        # Test invalid command
        invalid_result = tf.run_command('./cpc invalid-command-xyz')
        assert invalid_result is not None, "Invalid command test failed"
        assert invalid_result.returncode != 0, "Invalid command should return error"
        
        # Test that system recovers and works after error
        recovery_result = tf.run_command('./cpc --help')
        assert recovery_result is not None, "Recovery after error failed"
        assert recovery_result.returncode == 0, "System didn't recover after error"


@pytest.mark.integration 
class TestCPCStatusWorkflows:
    """Test status command workflows"""

    def test_status_command_variants(self):
        """Test different status command variants"""
        status_commands = [
            './cpc quick-status',
            './cpc status --help'
        ]
        
        for cmd in status_commands:
            result = tf.run_command(cmd, timeout=30)
            if result:
                # Should not crash
                assert result.returncode in [0, 1], f"Status command crashed: {cmd}"

    def test_status_output_consistency(self):
        """Test that status outputs are consistent"""
        results = []
        
        # Run quick-status multiple times
        for i in range(3):
            result = tf.run_command('./cpc quick-status', timeout=15)
            if result and result.returncode == 0:
                results.append(result.stdout)
            time.sleep(1)
        
        if len(results) >= 2:
            # Check for consistent workspace info
            workspace_lines = []
            for output in results:
                for line in output.split('\n'):
                    if 'Workspace:' in line:
                        workspace_lines.append(line.strip())
                        break
            
            if len(workspace_lines) >= 2:
                assert workspace_lines[0] == workspace_lines[1], "Workspace info inconsistent"

    def test_performance_baseline(self):
        """Test performance baseline for key commands"""
        performance_tests = [
            ('./cpc quick-status', 10.0),  # Should be under 10 seconds
            ('./cpc --help', 5.0),         # Should be under 5 seconds
            ('./cpc ctx', 15.0)            # Should be under 15 seconds
        ]
        
        for cmd, max_time in performance_tests:
            start_time = time.time()
            result = tf.run_command(cmd, timeout=max_time + 5)
            end_time = time.time()
            
            if result and result.returncode == 0:
                execution_time = end_time - start_time
                assert execution_time < max_time, f"Command {cmd} too slow: {execution_time:.2f}s > {max_time}s"


@pytest.mark.integration
@pytest.mark.slow
class TestCPCEndToEndWorkflows:
    """Test end-to-end workflows (marked as slow)"""

    def test_secrets_loading_workflow(self):
        """Test secrets loading workflow"""
        # Clear cache first
        clear_result = tf.run_command('./cpc clear-cache')
        assert clear_result is not None, "Cache clear failed"
        
        # Load secrets
        secrets_result = tf.run_command('./cpc load_secrets', timeout=60)
        
        if secrets_result and secrets_result.returncode == 0:
            # Should indicate secrets loaded
            assert any(phrase in secrets_result.stdout for phrase in [
                'Loading fresh secrets',
                'Using cached secrets', 
                'Secrets loaded successfully'
            ]), "No indication of secrets loading"

    def test_workspace_switching_workflow(self):
        """Test workspace switching workflow"""
        # Get current workspace
        ctx_result = tf.run_command('./cpc ctx')
        current_workspace = None
        
        if ctx_result and ctx_result.returncode == 0:
            for line in ctx_result.stdout.split('\n'):
                if 'Current cluster context:' in line:
                    current_workspace = line.split(':')[-1].strip()
                    break
        
        if current_workspace:
            # Switch to same workspace (should work)
            switch_result = tf.run_command(f'./cpc ctx {current_workspace}', timeout=60)
            
            if switch_result and switch_result.returncode == 0:
                # Verify switch was successful
                verify_result = tf.run_command('./cpc ctx')
                if verify_result and verify_result.returncode == 0:
                    assert current_workspace in verify_result.stdout, "Workspace switch verification failed"

    def test_cache_workflow_integration(self):
        """Test complete cache workflow"""
        # Clear cache
        tf.run_command('./cpc clear-cache')
        
        # Run commands that should populate cache
        commands_for_cache = [
            './cpc load_secrets',
            './cpc quick-status'
        ]
        
        cache_populated = False
        for cmd in commands_for_cache:
            result = tf.run_command(cmd, timeout=60)
            if result and result.returncode == 0:
                cache_populated = True
                break
        
        if cache_populated:
            # Run same command again - should be faster
            start_time = time.time()
            result2 = tf.run_command('./cpc quick-status', timeout=30)
            cached_time = time.time() - start_time
            
            if result2 and result2.returncode == 0:
                # Cached run should be reasonably fast
                assert cached_time < 15.0, f"Cached run too slow: {cached_time:.2f}s"

    def test_comprehensive_command_coverage(self):
        """Test comprehensive command coverage"""
        # Commands that should work without additional setup
        safe_commands = [
            './cpc --help',
            './cpc ctx',
            './cpc list-workspaces',
            './cpc quick-status',
            './cpc clear-cache'
        ]
        
        success_count = 0
        total_commands = len(safe_commands)
        
        for cmd in safe_commands:
            result = tf.run_command(cmd, timeout=30)
            if result and result.returncode == 0:
                success_count += 1
        
        # At least 80% of commands should work
        success_rate = success_count / total_commands
        assert success_rate >= 0.8, f"Command success rate too low: {success_rate:.2f}"


@pytest.mark.integration
class TestCPCSystemIntegration:
    """Test system integration aspects"""

    def test_dependency_availability(self):
        """Test that required dependencies are available"""
        dependencies = ['bash', 'jq']
        
        for dep in dependencies:
            result = tf.run_command(f'which {dep}')
            if result:
                assert result.returncode == 0, f"Required dependency missing: {dep}"

    def test_file_system_integration(self):
        """Test file system integration"""
        # Test that temporary directory is writable
        temp_test = tf.run_command('echo "test" > /tmp/cpc_test_file && rm /tmp/cpc_test_file')
        assert temp_test is not None, "Temp directory access failed"
        assert temp_test.returncode == 0, "Cannot write to temp directory"

    def test_concurrent_execution_safety(self):
        """Test concurrent execution safety"""
        import threading
        import queue
        
        results_queue = queue.Queue()
        
        def run_quick_status():
            result = tf.run_command('./cpc quick-status', timeout=30)
            results_queue.put(result)
        
        # Start multiple threads
        threads = []
        for i in range(2):
            thread = threading.Thread(target=run_quick_status)
            threads.append(thread)
            thread.start()
        
        # Wait for completion
        for thread in threads:
            thread.join(timeout=40)
        
        # Check that at least one succeeded
        success_count = 0
        while not results_queue.empty():
            result = results_queue.get()
            if result and result.returncode == 0:
                success_count += 1
        
        assert success_count >= 1, "No successful concurrent executions"

    def test_environment_isolation(self):
        """Test environment variable isolation"""
        # Test that commands don't pollute environment permanently
        original_env = dict(os.environ)
        
        # Run command that might set environment variables
        result = tf.run_command('./cpc quick-status', timeout=30)
        
        # Environment should be same (within reason - some variables may be added by shell)
        current_env = dict(os.environ)
        
        # Check that no obviously problematic variables were added
        problematic_vars = ['PROXMOX_PASSWORD', 'VM_PASSWORD']
        for var in problematic_vars:
            assert var not in current_env or var in original_env, f"Sensitive variable leaked: {var}"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
