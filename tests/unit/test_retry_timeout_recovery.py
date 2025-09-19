import pytest
from pathlib import Path

class TestRetryLogic:
    """Tests for retry.sh."""

    def test_retry_succeeds_on_third_attempt(self, bash_helper, tmp_path):
        counter_file = tmp_path / "counter.txt"
        
        fail_twice_script = tmp_path / "fail_twice.sh"
        fail_twice_script.write_text(f"""
#!/bin/bash
count=$(cat {counter_file} 2>/dev/null || echo 0)
count=$((count + 1))
echo $count > {counter_file}
if [ "$count" -lt 3 ]; then exit 1; else exit 0; fi
        """)
        fail_twice_script.chmod(0o755)

        result = bash_helper(f"retry_execute '{fail_twice_script}' 3")
        assert result.returncode == 0
        assert "failed on attempt 1" in result.stderr
        assert "succeeded on attempt 3" in result.stdout        

class TestTimeoutLogic:
    """Tests for timeout.sh."""

    def test_timeout_fails_if_command_is_slow(self, bash_helper):
        result = bash_helper("timeout_execute 1 'sleep 3'")
        assert result.returncode != 0
        assert "Command execution timed out" in result.stderr
