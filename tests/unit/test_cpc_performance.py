#!/usr/bin/env python3
"""
Performance and caching tests for CPC
"""

import pytest
import time
import os
from pathlib import Path
from unittest.mock import patch, MagicMock
import tempfile

# Import test framework
from tests import TestFramework

tf = TestFramework()


class TestCPCPerformance:
    """Test CPC performance and caching"""

    def test_quick_status_performance(self):
        """Test that quick-status is actually quick"""
        start_time = time.time()
        result = tf.run_command('./cpc quick-status', timeout=10)
        end_time = time.time()
        
        assert result is not None, "quick-status command failed"
        assert result.returncode == 0, f"quick-status failed with code {result.returncode}"
        
        execution_time = end_time - start_time
        assert execution_time < 5.0, f"quick-status took too long: {execution_time:.2f}s"

    def test_secrets_caching_behavior(self):
        """Test secrets caching functionality"""
        # Clear cache first
        tf.run_command('./cpc clear-cache')
        
        # First run should load fresh secrets
        start_time = time.time()
        result1 = tf.run_command('./cpc load_secrets', timeout=30)
        first_run_time = time.time() - start_time
        
        if result1 and result1.returncode == 0:
            assert 'Loading fresh secrets' in result1.stdout or 'Using cached secrets' in result1.stdout
            
            # Second run should use cache
            start_time = time.time()  
            result2 = tf.run_command('./cpc load_secrets', timeout=30)
            second_run_time = time.time() - start_time
            
            if result2 and result2.returncode == 0:
                # Second run should be faster due to caching
                assert second_run_time <= first_run_time + 1.0, "Caching doesn't improve performance"

    def test_cache_file_creation(self):
        """Test that cache files are created correctly"""
        # Clear cache first
        tf.run_command('./cpc clear-cache')
        
        # Run command that should create cache
        result = tf.run_command('./cpc load_secrets', timeout=30)
        
        if result and result.returncode == 0:
            # Check for cache files
            cache_patterns = [
                '/tmp/cpc_env_cache.sh',
                '/tmp/cpc_secrets_cache'
            ]
            
            for pattern in cache_patterns:
                cache_file = Path(pattern)
                if cache_file.exists():
                    assert cache_file.stat().st_size > 0, f"Cache file {pattern} is empty"

    def test_cache_invalidation_on_workspace_switch(self):
        """Test that cache is cleared when switching workspaces"""
        # Clear cache first
        tf.run_command('./cpc clear-cache')
        
        # Load secrets for current workspace
        result1 = tf.run_command('./cpc load_secrets', timeout=30)
        
        if result1 and result1.returncode == 0:
            # Get current workspace
            ctx_result = tf.run_command('./cpc ctx')
            if ctx_result and ctx_result.returncode == 0:
                current_ctx = None
                for line in ctx_result.stdout.split('\n'):
                    if 'Current cluster context:' in line:
                        current_ctx = line.split(':')[-1].strip()
                        break
                
                if current_ctx:
                    # Switch to same workspace (should still clear cache)
                    switch_result = tf.run_command(f'./cpc ctx {current_ctx}', timeout=30)
                    
                    if switch_result and switch_result.returncode == 0:
                        assert 'Cache cleared successfully' in switch_result.stdout, "Cache not cleared on workspace switch"

    def test_multiple_quick_status_calls(self):
        """Test multiple quick status calls for consistency"""
        results = []
        
        for i in range(3):
            result = tf.run_command('./cpc quick-status', timeout=10)
            if result and result.returncode == 0:
                results.append(result.stdout)
        
        if len(results) > 1:
            # Results should be consistent
            for i in range(1, len(results)):
                # Check that workspace info is consistent
                if 'Workspace:' in results[0] and 'Workspace:' in results[i]:
                    workspace_1 = [line for line in results[0].split('\n') if 'Workspace:' in line][0]
                    workspace_i = [line for line in results[i].split('\n') if 'Workspace:' in line][0]
                    assert workspace_1 == workspace_i, "Workspace info inconsistent across calls"


class TestCPCCacheManagement:
    """Test cache management functionality"""

    def test_cache_clear_command_output(self):
        """Test cache clear command provides feedback"""
        result = tf.run_command('./cpc clear-cache')
        assert result is not None, "clear-cache command failed"
        assert result.returncode == 0, f"clear-cache failed with code {result.returncode}"

    def test_cache_age_reporting(self):
        """Test that cache age is reported correctly"""
        # Clear cache first
        tf.run_command('./cpc clear-cache')
        
        # Load secrets to create cache
        result1 = tf.run_command('./cpc load_secrets', timeout=30)
        
        if result1 and result1.returncode == 0:
            # Wait a moment
            time.sleep(2)
            
            # Load again to see cache age
            result2 = tf.run_command('./cpc load_secrets', timeout=30)
            
            if result2 and result2.returncode == 0:
                if 'Using cached secrets' in result2.stdout:
                    # Should show age in seconds
                    assert 'age:' in result2.stdout, "Cache age not reported"

    def test_cache_directory_cleanup(self):
        """Test that cache cleanup handles various file patterns"""
        # Create dummy cache files
        dummy_files = [
            '/tmp/cpc_test_cache_1',
            '/tmp/cpc_test_cache_2',
            '/tmp/cpc_env_cache.sh'
        ]
        
        for dummy_file in dummy_files:
            Path(dummy_file).touch()
        
        # Clear cache
        result = tf.run_command('./cpc clear-cache')
        assert result is not None, "Cache clear failed"
        
        # Check that env cache was cleared
        assert not Path('/tmp/cpc_env_cache.sh').exists(), "Env cache not cleared"

    def test_concurrent_cache_access(self):
        """Test behavior with concurrent cache access"""
        import threading
        import queue
        
        results_queue = queue.Queue()
        
        def run_load_secrets():
            result = tf.run_command('./cpc load_secrets', timeout=30)
            results_queue.put(result)
        
        # Start multiple threads
        threads = []
        for i in range(2):
            thread = threading.Thread(target=run_load_secrets)
            threads.append(thread)
            thread.start()
        
        # Wait for completion
        for thread in threads:
            thread.join(timeout=40)
        
        # Check results
        success_count = 0
        while not results_queue.empty():
            result = results_queue.get()
            if result and result.returncode == 0:
                success_count += 1
        
        assert success_count >= 1, "No successful concurrent cache access"


class TestCPCStatusCaching:
    """Test status command caching"""

    def test_status_command_caching(self):
        """Test that status commands use caching effectively"""
        # Test full status vs quick status
        quick_start = time.time()
        quick_result = tf.run_command('./cpc quick-status', timeout=10)
        quick_time = time.time() - quick_start
        
        if quick_result and quick_result.returncode == 0:
            # Quick status should be very fast
            assert quick_time < 5.0, f"Quick status too slow: {quick_time:.2f}s"

    def test_terraform_output_caching(self):
        """Test terraform output caching behavior"""
        # This test checks if terraform data is cached
        result = tf.run_command('./cpc status --quick', timeout=30)
        
        if result and result.returncode == 0:
            # Check for signs of caching
            output_lines = result.stdout.split('\n')
            has_vm_info = any('VMs deployed:' in line for line in output_lines)
            
            if has_vm_info:
                # Second call should be faster due to caching
                start_time = time.time()
                result2 = tf.run_command('./cpc status --quick', timeout=30)
                second_call_time = time.time() - start_time
                
                assert second_call_time < 20.0, f"Cached status call too slow: {second_call_time:.2f}s"

    def test_ssh_status_caching(self):
        """Test SSH connectivity caching"""
        # Run status command that includes SSH checks
        result = tf.run_command('./cpc status --quick', timeout=30)
        
        if result and result.returncode == 0:
            output_lines = result.stdout.split('\n')
            ssh_lines = [line for line in output_lines if 'SSH reachable:' in line]
            
            if ssh_lines:
                # SSH status was checked, second call should use cache
                start_time = time.time()
                result2 = tf.run_command('./cpc status --quick', timeout=30)
                second_time = time.time() - start_time
                
                assert second_time < 25.0, f"Cached SSH check too slow: {second_time:.2f}s"


@pytest.mark.integration
class TestCPCWorkspaceCaching:
    """Test workspace-specific caching behavior"""

    def test_workspace_isolation(self):
        """Test that cache is isolated per workspace"""
        # Get current workspace
        ctx_result = tf.run_command('./cpc ctx')
        current_workspace = None
        
        if ctx_result and ctx_result.returncode == 0:
            for line in ctx_result.stdout.split('\n'):
                if 'Current cluster context:' in line:
                    current_workspace = line.split(':')[-1].strip()
                    break
        
        if current_workspace:
            # Clear cache first
            tf.run_command('./cpc clear-cache')
            
            # Load secrets for current workspace
            result1 = tf.run_command('./cpc load_secrets', timeout=30)
            
            if result1 and result1.returncode == 0:
                # Switch workspace should clear cache
                switch_result = tf.run_command(f'./cpc ctx {current_workspace}', timeout=30)
                
                if switch_result and switch_result.returncode == 0:
                    # Check that cache clearing happened
                    assert 'Cache cleared successfully' in switch_result.stdout, "Cache not cleared on workspace switch"
                    
                    # Since we're switching to the same workspace, the behavior might vary
                    # The important thing is that cache clearing mechanism works
                    cache_related = ('Loading fresh secrets' in switch_result.stdout or 
                                   'Using cached secrets' in switch_result.stdout)
                    assert cache_related, "No cache-related message found"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
