import pytest
import subprocess
import os
from pathlib import Path
import time

# --- Test Fixtures ---

@pytest.fixture
def bash_helper(tmp_path: Path):
    """A fixture to provide a helper for running bash script functions."""
    
    # Create a mock logging.sh since cache_utils depends on it
    lib_dir = tmp_path / "lib"
    lib_dir.mkdir()
    (lib_dir / "logging.sh").write_text("""
#!/bin/bash
log_debug() { echo "DEBUG: $1"; }
log_success() { echo "SUCCESS: $1"; }
    """)

    # The script to be tested
    script_to_test = lib_dir / "cache_utils.sh"
    
    # Copy the real script into the mock environment
    original_script_path = Path("/home/abevz/Projects/kubernetes/CreatePersonalCluster/lib/cache_utils.sh")
    if original_script_path.exists():
        script_to_test.write_text(original_script_path.read_text())
    else:
        pytest.fail(f"Original script not found at {original_script_path}")

    def run_bash_command(command: str, env: dict = None):
        """Inner function to execute a bash command in a sourced environment."""
        if env is None:
            env = os.environ.copy()
        
        # Ensure REPO_PATH is set for the script's sourcing logic
        env["REPO_PATH"] = str(tmp_path)

        # The command sources dependencies and then runs the requested function
        full_command = f"""
        set -e
        source "{lib_dir / 'logging.sh'}"
        source "{script_to_test}"
        {command}
        """
        
        return subprocess.run(
            ['bash', '-c', full_command],
            capture_output=True,
            text=True,
            env=env,
            timeout=5
        )

    return run_bash_command

# --- Test Cases ---

class TestCacheUtils:
    """Test suite for functions in lib/cache_utils.sh."""

    def test_update_cache_timestamp_creates_and_writes_file(self, bash_helper, tmp_path: Path):
        """Verify that update_cache_timestamp creates a file and writes the correct data."""
        cache_file = tmp_path / "test.cache"
        test_data = "my-secret-data"

        result = bash_helper(f'update_cache_timestamp "{cache_file}" "{test_data}"')

        assert result.returncode == 0
        assert cache_file.exists()
        
        content = cache_file.read_text()
        assert test_data in content
        assert "Cache updated" in content

    def test_check_cache_freshness_missing_files(self, bash_helper, tmp_path: Path):
        """Verify freshness check returns 'missing' if a file doesn't exist."""
        secrets_file = tmp_path / "secrets.yaml"
        secrets_file.touch()

        result = bash_helper(f'check_cache_freshness "{tmp_path / "nonexistent.cache"}" "{secrets_file}"')
        
        assert result.returncode == 1
        assert "missing" in result.stdout.strip()

    def test_check_cache_freshness_stale(self, bash_helper, tmp_path: Path):
        """Verify freshness check returns 'stale' if the secrets file is newer."""
        cache_file = tmp_path / "test.cache"
        secrets_file = tmp_path / "secrets.yaml"

        # Create files and manually set older timestamp for the cache file
        secrets_file.write_text("new secrets")
        cache_file.write_text("old data")
        
        # Manually set cache_file's modification time to be in the past
        older_time = time.time() - 10
        os.utime(cache_file, (older_time, older_time))

        result = bash_helper(f'check_cache_freshness "{cache_file}" "{secrets_file}"')

        assert result.returncode == 1
        assert "stale" in result.stdout.strip()

    def test_check_cache_freshness_fresh(self, bash_helper, tmp_path: Path):
        """Verify freshness check returns 'fresh' if the cache is newer."""
        cache_file = tmp_path / "test.cache"
        secrets_file = tmp_path / "secrets.yaml"

        # Create secrets file first, then cache file
        secrets_file.write_text("new secrets")
        time.sleep(0.1)
        cache_file.write_text("new data")

        result = bash_helper(f'check_cache_freshness "{cache_file}" "{secrets_file}"')

        assert result.returncode == 0
        assert "fresh" in result.stdout.strip()

    def test_clear_all_caches_removes_files(self, bash_helper, monkeypatch):
        """Verify that clear_all_caches removes the specified cache files."""
        # We need to operate in /tmp since the paths are hardcoded in the script
        # Use monkeypatch to ensure we don't affect the user's real /tmp files
        
        # Create dummy cache files in the real /tmp
        dummy_files = [
            "/tmp/cpc_secrets_cache",
            "/tmp/cpc_env_cache.sh",
            "/tmp/cpc_status_cache",
            "/tmp/cpc_ssh_cache",
            "/tmp/cpc_test_cache_123" # To match the glob
        ]
        
        for f in dummy_files:
            Path(f).touch()

        result = bash_helper('clear_all_caches')

        assert result.returncode == 0
        assert "All caches cleared successfully" in result.stdout
        
        for f in dummy_files:
            assert not Path(f).exists()
