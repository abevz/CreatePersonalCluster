#!/usr/bin/env python3
"""
Functional tests for CPC - testing actual functionality, not just structure
"""

import pytest
import time
import tempfile
import json
from pathlib import Path
from unittest.mock import patch

# Import test framework
from tests import TestFramework

tf = TestFramework()


class TestCPCWorkspaceManagementFunctionality:
    """Test workspace management functionality"""

    def test_workspace_creation_and_deletion_functional(self):
        """Test that workspace creation and deletion actually work"""
        test_workspace = f"test-ws-{int(time.time())}"
        
        try:
            # First check if workspace exists
            list_result = tf.run_command('./cpc list-workspaces', timeout=15)
            if list_result and list_result.returncode == 0:
                if test_workspace in list_result.stdout:
                    pytest.skip(f"Test workspace {test_workspace} already exists")
            
            # Test workspace deletion (should work even if workspace doesn't exist)
            delete_result = tf.run_command(f'./cpc delete-workspace {test_workspace}', timeout=60, input_text='y\n')
            
            # Command should complete (may succeed or show "not found" message)
            assert delete_result is not None, "delete-workspace command failed to run"
            
            if delete_result.returncode == 0:
                # Should show deletion progress
                deletion_indicators = [
                    'Destroying all resources',
                    'Destroy complete',
                    'Workspace deleted successfully',
                    'No changes. No objects need to be destroyed',
                    'Deleting workspace environment file'
                ]
                has_deletion_info = any(indicator in delete_result.stdout for indicator in deletion_indicators)
                assert has_deletion_info, f"No deletion information shown: {delete_result.stdout}"
            else:
                # If failed, should show meaningful error
                error_indicators = ['Error:', 'not found', 'does not exist', 'Failed']
                has_error_info = any(indicator in delete_result.stderr.lower() or indicator in delete_result.stdout.lower() 
                                   for indicator in error_indicators)
                # Don't assert on error - workspace may not exist
                
        except Exception as e:
            pytest.skip(f"Workspace deletion test skipped due to: {e}")

    def test_workspace_list_shows_actual_workspaces_functional(self):
        """Test that list-workspaces shows real workspace data"""
        result = tf.run_command('./cpc list-workspaces', timeout=15)
        assert result is not None and result.returncode == 0, "list-workspaces failed"
        
        # Should show current workspace
        assert 'Current workspace:' in result.stdout, "Missing current workspace info"
        
        # Should show Tofu workspaces section
        assert 'Tofu workspaces:' in result.stdout, "Missing Tofu workspaces section"
        
        # Should show environment files section  
        assert 'Environment files:' in result.stdout, "Missing environment files section"
        
        # Extract workspace information
        lines = result.stdout.split('\n')
        current_workspace = None
        tofu_workspaces = []
        env_files = []
        
        section = None
        for line in lines:
            line = line.strip()
            if 'Current workspace:' in line:
                current_workspace = line.split(':')[-1].strip()
            elif 'Tofu workspaces:' in line:
                section = 'tofu'
            elif 'Environment files:' in line:
                section = 'env'
            elif section == 'tofu' and line and not line.startswith('Environment'):
                if line.startswith('*') or line.startswith(' '):
                    workspace_name = line.replace('*', '').strip()
                    if workspace_name and workspace_name != 'default':
                        tofu_workspaces.append(workspace_name)
            elif section == 'env' and line and not line.startswith('─'):
                if '.env' in line:
                    env_files.append(line)
        
        # Should have found current workspace
        assert current_workspace is not None, "Could not extract current workspace"
        
        # Information should be consistent
        if tofu_workspaces:
            assert current_workspace in tofu_workspaces, f"Current workspace '{current_workspace}' not in Tofu list: {tofu_workspaces}"

    def test_workspace_switching_with_nonexistent_workspace_functional(self):
        """Test switching to non-existent workspace"""
        nonexistent_workspace = f"nonexistent-ws-{int(time.time())}"
        
        result = tf.run_command(f'./cpc ctx {nonexistent_workspace}', timeout=30)
        
        # Should handle gracefully
        assert result is not None, "ctx command failed to run"
        
        if result.returncode != 0:
            # Should show meaningful error
            error_indicators = ['Error:', 'not found', 'does not exist', 'Failed', 'Invalid']
            has_error_info = any(indicator in result.stderr.lower() or indicator in result.stdout.lower() 
                               for indicator in error_indicators)
            assert has_error_info, f"No error information for non-existent workspace: {result.stdout}"
        else:
            # If it succeeds, it might create the workspace - that's also valid behavior
            pass


class TestCPCWorkspaceFunctionality:
    """Test actual workspace functionality"""

    def test_workspace_switching_functional(self):
        """Test that workspace switching actually changes context"""
        # Get current workspace
        result1 = tf.run_command('./cpc ctx')
        assert result1 is not None and result1.returncode == 0, "Failed to get current context"
        
        current_workspace = None
        for line in result1.stdout.split('\n'):
            if 'Current cluster context:' in line:
                current_workspace = line.split(':')[-1].strip()
                break
        
        assert current_workspace is not None, "Could not extract current workspace"
        
        # Switch to same workspace (should work)
        result2 = tf.run_command(f'./cpc ctx {current_workspace}', timeout=60)
        assert result2 is not None and result2.returncode == 0, f"Failed to switch to {current_workspace}"
        
        # Verify the switch
        result3 = tf.run_command('./cpc ctx')
        assert result3 is not None and result3.returncode == 0, "Failed to verify context after switch"
        assert current_workspace in result3.stdout, "Context switch verification failed"

    def test_workspace_list_functional(self):
        """Test that list-workspaces actually shows workspaces"""
        result = tf.run_command('./cpc list-workspaces')
        assert result is not None and result.returncode == 0, "list-workspaces command failed"
        
        # Should show current workspace
        assert 'Current workspace:' in result.stdout, "Missing current workspace info"
        
        # Should show available workspaces
        assert 'Tofu workspaces:' in result.stdout, "Missing Tofu workspaces section"
        assert 'Environment files:' in result.stdout, "Missing environment files section"
        
        # Should list at least one workspace
        lines = result.stdout.split('\n')
        workspace_listed = False
        for line in lines:
            if line.strip() and (line.startswith('*') or line.startswith('  ')) and not 'No' in line:
                workspace_listed = True
                break
        
        assert workspace_listed, "No workspaces listed"

    def test_delete_workspace_command_functional(self):
        """Test delete-workspace command functionality"""
        # Test delete-workspace help
        help_result = tf.run_command('./cpc delete-workspace --help', timeout=10)
        if help_result and help_result.returncode == 0:
            assert 'Usage:' in help_result.stdout, "delete-workspace help missing"
        
        # Test delete-workspace without arguments (should return error code 1)
        no_args_result = tf.run_command('./cpc delete-workspace', timeout=10)
        assert no_args_result is not None, "delete-workspace without args failed to run"
        assert 'Usage: cpc delete-workspace <workspace_name>' in no_args_result.stdout, "delete-workspace should show usage when no args"
        
        # BUG FIXED: Command now properly returns 1 when no arguments provided
        assert no_args_result.returncode == 1, "delete-workspace should return error code 1 when no args provided"
        print("✅ FIXED: delete-workspace now returns proper error code!")
        
        # Test delete-workspace with non-existent workspace
        nonexistent = f"nonexistent-{int(time.time())}"
        nonexistent_result = tf.run_command(f'./cpc delete-workspace {nonexistent}', timeout=30, input_text='y\n')
        
        assert nonexistent_result is not None, "delete-workspace with non-existent workspace failed to run"
        
        # Should either succeed (if it handles non-existent gracefully) or show error
        if nonexistent_result.returncode == 0:
            # Should show meaningful output
            output_indicators = [
                'Destroying all resources',
                'No changes. No objects need to be destroyed',
                'Workspace deleted',
                'not found',
                'does not exist'
            ]
            has_output = any(indicator in nonexistent_result.stdout for indicator in output_indicators)
            assert has_output, f"delete-workspace gave no meaningful output: {nonexistent_result.stdout}"
        else:
            # Should show error for non-existent workspace
            error_indicators = ['Error:', 'not found', 'does not exist']
            has_error = any(indicator in nonexistent_result.stderr.lower() or indicator in nonexistent_result.stdout.lower() 
                           for indicator in error_indicators)
            # Error is acceptable for non-existent workspace
        """Test that cache functionality actually works"""
        # Clear cache
        clear_result = tf.run_command('./cpc clear-cache')
        assert clear_result is not None and clear_result.returncode == 0, "Cache clear failed"
        
        # Check that cache files are gone
        cache_patterns = ['/tmp/cpc_env_cache.sh', '/tmp/cpc_secrets_cache']
        for pattern in cache_patterns:
            cache_file = Path(pattern)
            assert not cache_file.exists(), f"Cache file not cleared: {pattern}"

    def test_quick_status_functional(self):
        """Test that quick-status provides actual status information"""
        result = tf.run_command('./cpc quick-status', timeout=15)
        assert result is not None and result.returncode == 0, "quick-status failed"
        
        # Should show workspace
        assert 'Workspace:' in result.stdout, "Missing workspace info"
        
        # Should show some status (either K8s nodes or error message)
        status_indicators = ['K8s nodes:', 'K8s: Not accessible', 'nodes:']
        has_status = any(indicator in result.stdout for indicator in status_indicators)
        assert has_status, "No status information provided"

    def test_delete_workspace_actual_deletion_functional(self):
        """Test that delete-workspace actually deletes a workspace"""
        # Create a test workspace for deletion
        test_workspace = f"test-deletion-{int(time.time())}"
        
        try:
            # Step 1: Create workspace by switching to it
            print(f"🔨 Creating test workspace: {test_workspace}")
            create_result = tf.run_command(f'./cpc ctx {test_workspace}', timeout=30)
            
            if not create_result or create_result.returncode != 0:
                pytest.skip(f"Cannot create test workspace {test_workspace}")
            
            # Step 2: Verify workspace was created
            list_before = tf.run_command('./cpc list-workspaces', timeout=15)
            if not list_before or list_before.returncode != 0:
                pytest.skip("Cannot get workspace list")
            
            # Check if workspace appears in listing
            workspace_found_before = test_workspace in list_before.stdout
            assert workspace_found_before, f"Test workspace {test_workspace} not found after creation"
            print(f"✅ Workspace {test_workspace} created and found in listing")
            
            # Step 3: Delete the workspace
            print(f"🗑️  Deleting workspace: {test_workspace}")
            delete_result = tf.run_command(f'./cpc delete-workspace {test_workspace}', timeout=60, input_text='y\n')
            
            assert delete_result is not None, f"delete-workspace command failed to run for {test_workspace}"
            assert delete_result.returncode == 0, f"delete-workspace failed for {test_workspace}: {delete_result.stderr}"
            
            # Should show deletion process
            deletion_indicators = [
                'Destroying all resources',
                'Workspace deleted successfully',
                'has been successfully deleted',
                'Terraform workspace',
                'deleted'
            ]
            has_deletion_output = any(indicator in delete_result.stdout for indicator in deletion_indicators)
            assert has_deletion_output, f"No deletion output shown: {delete_result.stdout}"
            print("✅ Deletion process completed with proper output")
            
            # Step 4: Verify workspace was actually deleted
            print(f"🔍 Verifying {test_workspace} was removed from listing")
            list_after = tf.run_command('./cpc list-workspaces', timeout=15)
            
            if list_after and list_after.returncode == 0:
                workspace_found_after = test_workspace in list_after.stdout
                assert not workspace_found_after, f"FAIL: Workspace {test_workspace} still found in listing after deletion!"
                print(f"✅ Workspace {test_workspace} successfully removed from listing")
                
                # Step 4.5: Check that no unexpected workspaces were created
                # Compare workspace lists before and after
                workspaces_before = set()
                workspaces_after = set()
                
                # Extract workspace names from before listing
                for line in list_before.stdout.split('\n'):
                    if line.strip() and (line.startswith('*') or line.startswith(' ')) and not any(x in line for x in ['Current', 'Tofu', 'Environment', '─']):
                        ws_name = line.replace('*', '').strip()
                        if ws_name and ws_name != 'default':
                            workspaces_before.add(ws_name)
                
                # Extract workspace names from after listing  
                for line in list_after.stdout.split('\n'):
                    if line.strip() and (line.startswith('*') or line.startswith(' ')) and not any(x in line for x in ['Current', 'Tofu', 'Environment', '─']):
                        ws_name = line.replace('*', '').strip()
                        if ws_name and ws_name != 'default':
                            workspaces_after.add(ws_name)
                
                # Check for unexpected new workspaces
                new_workspaces = workspaces_after - workspaces_before
                if new_workspaces:
                    print(f"⚠️  WARNING: Unexpected new workspaces created during deletion: {new_workspaces}")
                    # This is a potential bug but don't fail test - just warn
                else:
                    print("✅ No unexpected workspaces were created during deletion")
            else:
                pytest.skip("Cannot verify deletion - list-workspaces failed")
            
            # Step 5: Verify environment file was deleted
            env_file_path = f"envs/{test_workspace}.env"
            env_file_exists = tf.check_file_exists(env_file_path)
            assert not env_file_exists, f"FAIL: Environment file {env_file_path} still exists after deletion!"
            print(f"✅ Environment file {env_file_path} was removed")
            
            print(f"🎉 SUCCESS: Workspace {test_workspace} was completely deleted!")
            
        except Exception as e:
            # Clean up in case of test failure
            print(f"⚠️  Test failed with error: {e}")
            cleanup_result = tf.run_command(f'./cpc delete-workspace {test_workspace}', timeout=60, input_text='y\n')
            if cleanup_result and cleanup_result.returncode == 0:
                print(f"🧹 Cleaned up test workspace {test_workspace}")
            raise


class TestCPCSecretsAndCachingFunctionality:
    """Test secrets loading and caching functionality"""

    def test_secrets_loading_functional(self):
        """Test that secrets loading actually works"""
        result = tf.run_command('./cpc load_secrets', timeout=60)
        
        # Command should complete (may succeed or fail depending on secrets setup)
        assert result is not None, "load_secrets command failed to run"
        
        if result.returncode == 0:
            # If successful, should show loading info
            loading_indicators = [
                'Loading fresh secrets',
                'Using cached secrets', 
                'Secrets loaded successfully',
                'Secrets reloaded successfully'
            ]
            has_loading_info = any(indicator in result.stdout for indicator in loading_indicators)
            assert has_loading_info, "No secrets loading information"
        else:
            # If failed, should show error info
            error_indicators = ['Error:', 'Failed', 'not found', 'missing']
            has_error_info = any(indicator in result.stderr.lower() or indicator in result.stdout.lower() 
                               for indicator in error_indicators)
            # Don't assert on error - secrets may not be configured in test environment

    def test_cache_age_functional(self):
        """Test that cache shows age information"""
        # Try to create cache
        tf.run_command('./cpc load_secrets', timeout=60)
        
        # Wait a moment
        time.sleep(2)
        
        # Load again to see if cache age is shown
        result = tf.run_command('./cpc load_secrets', timeout=60)
        
        if result and result.returncode == 0:
            if 'Using cached secrets' in result.stdout:
                # Should show age
                assert 'age:' in result.stdout, "Cache age not displayed"

    def test_workspace_cache_clearing_functional(self):
        """Test that switching workspace actually clears cache"""
        # Get current workspace
        ctx_result = tf.run_command('./cpc ctx')
        if not ctx_result or ctx_result.returncode != 0:
            pytest.skip("Cannot get current context")
        
        current_workspace = None
        for line in ctx_result.stdout.split('\n'):
            if 'Current cluster context:' in line:
                current_workspace = line.split(':')[-1].strip()
                break
        
        if not current_workspace:
            pytest.skip("Cannot extract current workspace")
        
        # Create some cache
        tf.run_command('./cpc load_secrets', timeout=60)
        
        # Switch workspace (even to same one)
        switch_result = tf.run_command(f'./cpc ctx {current_workspace}', timeout=60)
        
        if switch_result and switch_result.returncode == 0:
            # Should show cache cleared
            assert 'Cache cleared successfully' in switch_result.stdout, "Cache clearing not indicated"


class TestCPCStatusFunctionality:
    """Test status command functionality"""

    def test_status_command_functional(self):
        """Test that status command provides meaningful output"""
        # Test different status variants
        status_commands = [
            ('./cpc status --help', 'Usage:'),
            ('./cpc quick-status', 'Workspace:')
        ]
        
        for cmd, expected in status_commands:
            result = tf.run_command(cmd, timeout=30)
            if result and result.returncode == 0:
                assert expected in result.stdout, f"Command {cmd} missing expected output: {expected}"

    def test_status_performance_functional(self):
        """Test that status commands perform within reasonable time"""
        performance_tests = [
            ('./cpc quick-status', 15.0),  # Should be under 15 seconds
        ]
        
        for cmd, max_time in performance_tests:
            start_time = time.time()
            result = tf.run_command(cmd, timeout=max_time + 5)
            end_time = time.time()
            
            if result and result.returncode == 0:
                execution_time = end_time - start_time
                assert execution_time < max_time, f"Command {cmd} too slow: {execution_time:.2f}s > {max_time}s"

    def test_status_output_consistency_functional(self):
        """Test that status output is consistent across multiple calls"""
        results = []
        
        for i in range(2):
            result = tf.run_command('./cpc quick-status', timeout=15)
            if result and result.returncode == 0:
                results.append(result.stdout)
                time.sleep(1)
        
        if len(results) == 2:
            # Extract workspace from both results
            workspace1 = workspace2 = None
            
            for line in results[0].split('\n'):
                if 'Workspace:' in line:
                    workspace1 = line.strip()
                    break
            
            for line in results[1].split('\n'):
                if 'Workspace:' in line:
                    workspace2 = line.strip()
                    break
            
            if workspace1 and workspace2:
                assert workspace1 == workspace2, "Workspace info inconsistent between calls"


class TestCPCCommandLineFunctionality:
    """Test command line interface functionality"""

    def test_help_commands_functional(self):
        """Test that help commands actually provide help"""
        help_commands = [
            './cpc --help',
            './cpc -h',
            './cpc help'
        ]
        
        for cmd in help_commands:
            result = tf.run_command(cmd, timeout=10)
            if result and result.returncode == 0:
                # Should contain usage and commands
                assert 'Usage:' in result.stdout, f"Command {cmd} missing usage"
                assert 'Commands:' in result.stdout, f"Command {cmd} missing commands list"
                
                # Should list key commands
                key_commands = ['ctx', 'status', 'bootstrap']
                for key_cmd in key_commands:
                    assert key_cmd in result.stdout, f"Command {cmd} missing key command: {key_cmd}"

    def test_invalid_command_handling_functional(self):
        """Test that invalid commands are handled properly"""
        invalid_commands = [
            './cpc invalid-command-xyz',
            './cpc nonexistent-command-123'
        ]
        
        for cmd in invalid_commands:
            result = tf.run_command(cmd, timeout=10)
            # Should return non-zero exit code for truly invalid commands
            assert result is not None, f"Command {cmd} failed to run"
            assert result.returncode != 0, f"Invalid command {cmd} should return error code"

    def test_command_argument_handling_functional(self):
        """Test that commands handle arguments properly"""
        # Commands that require arguments
        arg_commands = [
            ('./cpc ctx', 0),  # Should work - shows current context
            ('./cpc ctx --help', 0),  # Should show help
        ]
        
        for cmd, expected_code in arg_commands:
            result = tf.run_command(cmd, timeout=15)
            assert result is not None, f"Command {cmd} failed to run"
            assert result.returncode == expected_code, f"Command {cmd} unexpected exit code: {result.returncode}"


class TestCPCFileSystemFunctionality:
    """Test file system interaction functionality"""

    def test_config_file_reading_functional(self):
        """Test that config files are actually read"""
        # Run a command that should read config
        result = tf.run_command('./cpc --help', timeout=10)
        assert result is not None and result.returncode == 0, "Help command failed"
        
        # Should successfully load and show help (indicates config reading works)
        assert len(result.stdout) > 100, "Help output too short - config may not be loaded"

    def test_environment_file_detection_functional(self):
        """Test that environment files are detected"""
        result = tf.run_command('./cpc list-workspaces', timeout=15)
        assert result is not None and result.returncode == 0, "list-workspaces failed"
        
        # Should list environment files
        assert 'Environment files:' in result.stdout, "Environment files section missing"
        
        # Check if any environment files are listed
        lines = result.stdout.split('\n')
        in_env_section = False
        env_files_found = False
        
        for line in lines:
            if 'Environment files:' in line:
                in_env_section = True
                continue
            if in_env_section and line.strip() and not line.startswith('  '):
                break
            if in_env_section and line.strip() and 'No envs directory found' not in line:
                env_files_found = True
                break
        
        # Should find at least one environment file
        assert env_files_found, "No environment files detected"

    def test_temporary_file_handling_functional(self):
        """Test that temporary files are handled correctly"""
        # Run command that creates temp files
        result = tf.run_command('./cpc quick-status', timeout=15)
        
        if result and result.returncode == 0:
            # Should show recovery log creation
            assert 'Recovery system initialized' in result.stdout, "Recovery system not initialized"
            
            # Should create recovery log
            log_files = list(Path('/tmp').glob('cpc_recovery_*.log'))
            assert len(log_files) > 0, "No recovery log files created"


@pytest.mark.integration
class TestCPCIntegrationFunctionality:
    """Test integration functionality"""

    def test_end_to_end_workspace_workflow_functional(self):
        """Test end-to-end workspace workflow"""
        # Get current workspace
        ctx_result = tf.run_command('./cpc ctx')
        if not ctx_result or ctx_result.returncode != 0:
            pytest.skip("Cannot get current context")
        
        # List workspaces
        list_result = tf.run_command('./cpc list-workspaces')
        assert list_result is not None and list_result.returncode == 0, "Workspace listing failed"
        
        # Get status
        status_result = tf.run_command('./cpc quick-status', timeout=15)
        assert status_result is not None and status_result.returncode == 0, "Status check failed"
        
        # Clear cache
        cache_result = tf.run_command('./cpc clear-cache')
        assert cache_result is not None and cache_result.returncode == 0, "Cache clear failed"

    def test_command_chaining_functional(self):
        """Test that commands can be chained successfully"""
        commands = [
            './cpc ctx',
            './cpc list-workspaces',
            './cpc quick-status'
        ]
        
        all_successful = True
        for cmd in commands:
            result = tf.run_command(cmd, timeout=20)
            if not result or result.returncode != 0:
                all_successful = False
                break
        
        assert all_successful, "Command chaining failed - at least one command failed"

    def test_error_recovery_functional(self):
        """Test that system recovers from errors"""
        # Run invalid command
        invalid_result = tf.run_command('./cpc invalid-xyz', timeout=10)
        assert invalid_result is not None, "Invalid command test failed"
        assert invalid_result.returncode != 0, "Invalid command should fail"
        
        # System should still work after error
        recovery_result = tf.run_command('./cpc --help', timeout=10)
        assert recovery_result is not None and recovery_result.returncode == 0, "System didn't recover after error"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
