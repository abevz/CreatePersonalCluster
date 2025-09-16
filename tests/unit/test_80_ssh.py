import pytest
import os
import subprocess
import shutil
from pathlib import Path

# --- Test Framework and Fixtures ---

class BashTestHelper:
    """Helper to run bash functions in an isolated, sourced environment."""
    def __init__(self, temp_repo_path: Path):
        self.temp_repo_path = temp_repo_path

    def run_bash_command(self, command: str, env: dict = None, cwd: Path = None, input_text: str = None):
        """Runs a bash command after sourcing all necessary scripts."""
        if cwd is None:
            cwd = self.temp_repo_path

        source_files = [
            f"source {(self.temp_repo_path / 'modules/00_core.sh').resolve()}",
            f"source {(self.temp_repo_path / 'modules/80_ssh.sh').resolve()}"
        ]
        
        sourcery = " && ".join(source_files)

        process_env = os.environ.copy()
        process_env["REPO_PATH"] = str(self.temp_repo_path)
        if env:
            process_env.update(env)

        full_command = f'bash -c "{sourcery} && {command}"'

        return subprocess.run(
            full_command,
            shell=True,
            capture_output=True,
            text=True,
            cwd=str(cwd),
            env=process_env,
            input=input_text,
            timeout=5
        )

@pytest.fixture(scope="function")
def temp_repo(tmp_path: Path, monkeypatch) -> Path:
    """Creates an isolated, temporary repository structure for testing."""
    repo_root = tmp_path
    modules_dir = repo_root / "modules"
    lib_dir = repo_root / "lib"
    inventory_dir = repo_root / "ansible" / "inventory"
    
    modules_dir.mkdir()
    lib_dir.mkdir()
    inventory_dir.mkdir(parents=True)

    project_root = Path("/home/abevz/Projects/kubernetes/CreatePersonalCluster")
    shutil.copy(project_root / "modules/80_ssh.sh", modules_dir)
    
    real_lib_path = project_root / "lib"
    for lib_file in real_lib_path.glob("*.sh"):
        shutil.copy(lib_file, lib_dir)

    core_mock_content = """#!/bin/bash
export REPO_ROOT='{repo_root}'
export SCRIPT_DIR='{script_dir}'
source \"{logging_sh}\" 
source \"{error_handling_sh}\" 
get_repo_path() {{ echo \"{repo_root}\"; }}
recovery_checkpoint() {{ :; }}
""".format(
        repo_root=str(repo_root),
        script_dir=str(repo_root),
        logging_sh=str(lib_dir / 'logging.sh'),
        error_handling_sh=str(lib_dir / 'error_handling.sh')
    )
    (modules_dir / "00_core.sh").write_text(core_mock_content)

    # Mock inventory script
    inventory_script = inventory_dir / "tofu_inventory.py"
    inventory_script.write_text("""#!/usr/bin/env python3
import json
import sys

if len(sys.argv) > 1 and sys.argv[1] == '--list':
    print(json.dumps({
        "_meta": {
            "hostvars": {
                "test-host-1.example.com": {"ansible_host": "10.0.0.1"},
                "test-host-2.example.com": {"ansible_host": "10.0.0.2"}
            }
        }
    }))
""")
    inventory_script.chmod(0o755)

    # Mock ssh-keygen
    (repo_root / "bin").mkdir()
    ssh_keygen_mock = repo_root / "bin" / "ssh-keygen"
    ssh_keygen_mock.write_text("#!/bin/bash\necho 'ssh-keygen mock'")
    ssh_keygen_mock.chmod(0o755)
    monkeypatch.setenv("PATH", str(repo_root / "bin") + os.pathsep + os.environ.get("PATH", ""))

    return repo_root

@pytest.fixture(scope="function")
def bash_helper(temp_repo: Path) -> BashTestHelper:
    return BashTestHelper(temp_repo)

# --- Test Classes ---

class TestSshClearHosts:
    def test_happy_path(self, bash_helper, temp_repo, monkeypatch):
        (temp_repo / ".ssh").mkdir()
        (temp_repo / ".ssh" / "known_hosts").write_text("test-host-1.example.com,10.0.0.1 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...")
        monkeypatch.setenv("HOME", str(temp_repo))

        result = bash_helper.run_bash_command("ssh_clear_hosts")
        assert result.returncode == 0
        assert "Successfully removed SSH known_hosts entries" in result.stdout

    def test_dry_run(self, bash_helper, temp_repo, monkeypatch):
        (temp_repo / ".ssh").mkdir()
        (temp_repo / ".ssh" / "known_hosts").write_text("test-host-1.example.com,10.0.0.1 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...")
        monkeypatch.setenv("HOME", str(temp_repo))

        result = bash_helper.run_bash_command("ssh_clear_hosts --dry-run")
        assert result.returncode == 0
        assert "Dry run mode. Will not remove entries." in result.stderr

    def test_no_known_hosts_file(self, bash_helper, temp_repo, monkeypatch):
        monkeypatch.setenv("HOME", str(temp_repo))
        result = bash_helper.run_bash_command("ssh_clear_hosts")
        assert result.returncode == 0
        assert "No ~/.ssh/known_hosts file found" in result.stderr

class TestSshClearMaps:
    def test_happy_path(self, bash_helper):
        result = bash_helper.run_bash_command("ssh_clear_maps")
        assert result.returncode == 0
        assert "SSH connection cleanup completed" in result.stdout

    def test_dry_run(self, bash_helper):
        result = bash_helper.run_bash_command("ssh_clear_maps --dry-run")
        assert result.returncode == 0
        assert "Dry run mode - showing what would be cleared" in result.stderr

class TestGetAnsibleInventoryJson:
    def test_success(self, bash_helper):
        result = bash_helper.run_bash_command("_get_ansible_inventory_json")
        assert result.returncode == 0
        assert '"_meta":' in result.stdout

    def test_script_not_found(self, bash_helper, temp_repo):
        (temp_repo / "ansible" / "inventory" / "tofu_inventory.py").unlink()
        result = bash_helper.run_bash_command("_get_ansible_inventory_json")
        assert result.returncode == 1
        assert "Inventory script not found" in result.stderr
