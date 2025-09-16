import pytest
import subprocess
import os
import shutil
from pathlib import Path

# --- Helper Class and Fixtures (following project conventions) ---

class BashTestHelper:
    """Helper class from other tests to run bash commands in an isolated environment."""
    def __init__(self, temp_repo_path: Path):
        self.temp_repo_path = temp_repo_path

    def run_bash_command(self, command: str, env: dict = None, cwd: Path = None):
        if cwd is None:
            cwd = self.temp_repo_path

        source_files = []
        lib_dir = self.temp_repo_path / "lib"
        for lib_file in sorted(lib_dir.glob("*.sh")):
            source_files.append(f"source {lib_file.resolve()}")
        
        source_files.append(f"source {(self.temp_repo_path / 'modules/00_core.sh').resolve()}")
        source_files.append(f"source {(self.temp_repo_path / 'modules/20_ansible.sh').resolve()}")
        source_files.append(f"source {(self.temp_repo_path / 'ansible/addons/addon_discovery.sh').resolve()}")
        source_files.append(f"source {(self.temp_repo_path / 'modules/50_cluster_ops.sh').resolve()}")

        sourcery = " && ".join(source_files)

        process_env = os.environ.copy()
        process_env["REPO_PATH"] = str(self.temp_repo_path)
        if env:
            process_env.update(env)

        full_command = f'bash -c "{sourcery} && {command}"'

        return subprocess.run(
            full_command, shell=True, capture_output=True, text=True, cwd=str(cwd), env=process_env
        )

@pytest.fixture(scope="function")
def temp_repo(tmp_path: Path) -> Path:
    repo_root = tmp_path
    (repo_root / "modules").mkdir()
    (repo_root / "lib").mkdir()
    (repo_root / "ansible" / "addons").mkdir(parents=True)
    (repo_root / "scripts").mkdir()
    (repo_root / "bin").mkdir()
    (repo_root / ".kube").mkdir()
    (repo_root / ".kube" / "config").touch()

    real_script_path = Path("/home/abevz/Projects/kubernetes/CreatePersonalCluster/modules/50_cluster_ops.sh")
    (repo_root / "modules" / "50_cluster_ops.sh").write_text(real_script_path.read_text())
    real_lib_path = Path("/home/abevz/Projects/kubernetes/CreatePersonalCluster/lib")
    for lib_file in real_lib_path.glob("*.sh"):
        (repo_root / "lib" / lib_file.name).write_text(lib_file.read_text())

    (repo_root / "ansible/addons/addon_discovery.sh").write_text("#!/bin/bash\naddon_discover_all() { :; }\naddon_display_interactive_menu() { echo \"metallb\"; }\naddon_validate_exists() { [[ \"$1\" == \"metallb\" || \"$1\" == \"all\" || \"$1\" == \"metrics-server\" ]] && return 0 || return 1; }\n")
    (repo_root / "modules" / "20_ansible.sh").write_text("#!/bin/bash\ncpc_ansible() { echo \"Mock cpc_ansible called with: $@\"; if [[ \"$FORCE_ANSIBLE_FAILURE\" == \"true\" ]]; then return 1; else return 0; fi; }\n")
    (repo_root / "modules" / "00_core.sh").write_text(f'#!/bin/bash\nload_secrets_cached() {{ return 0; }}\nget_repo_path() {{ echo "{str(repo_root)}"; }}\n')
    (repo_root / "lib" / "timeout.sh").write_text("#!/bin/bash\ntimeout_execute() { if [[ \"$1\" == *\"read -r\"* ]]; then return 0; else eval \"$1\"; fi; }\n")
    (repo_root / "lib" / "recovery.sh").write_text("#!/bin/bash\nrecovery_execute() { eval \"$1\"; }\nrecovery_checkpoint() { :; }\n")
    get_dns_script = repo_root / "scripts" / "get_dns_server.sh"
    get_dns_script.write_text("#!/bin/bash\necho 1.1.1.1")
    get_dns_script.chmod(0o755)

    # FIX: Default kubectl mock needs to handle get pods for validation
    mock_kubectl = """
    #!/bin/bash
    if [[ \"$1\" == "get" && \"$2\" == "pods" ]]; then
        echo "pod-123 Running"
        exit 0
    fi
    # Default success for other commands like cluster-info
    exit 0
    """
    (repo_root / "bin" / "kubectl").write_text(mock_kubectl)
    (repo_root / "bin" / "kubectl").chmod(0o755)

    return repo_root

@pytest.fixture(scope="function")
def bash_helper(temp_repo: Path, monkeypatch) -> BashTestHelper:
    monkeypatch.setenv("KUBECONFIG", str(temp_repo / ".kube" / "config"))
    monkeypatch.setenv("PATH", str(temp_repo / "bin") + os.pathsep + os.environ.get("PATH", ""))
    return BashTestHelper(temp_repo)

# --- Test Classes ---

class TestClusterOpsUpgradeAddons:
    def test_happy_path_with_arg(self, bash_helper):
        result = bash_helper.run_bash_command("cluster_ops_upgrade_addons metallb")
        assert result.returncode == 0, f"STDERR: {result.stderr}"
        assert "Validation successful: Found running pods for 'metallb'" in result.stdout

    def test_interactive_menu_path(self, bash_helper):
        result = bash_helper.run_bash_command("cluster_ops_upgrade_addons")
        assert result.returncode == 0, f"STDERR: {result.stderr}"
        assert "Validation successful: Found running pods for 'metallb'" in result.stdout

    def test_invalid_addon_name(self, bash_helper):
        result = bash_helper.run_bash_command("cluster_ops_upgrade_addons fake-addon")
        assert result.returncode == 1, f"STDERR: {result.stderr}"
        assert "Usage: cpc upgrade-addons" in result.stdout

    def test_ansible_failure_path(self, bash_helper):
        result = bash_helper.run_bash_command("cluster_ops_upgrade_addons metallb", env={"FORCE_ANSIBLE_FAILURE": "true"})
        assert result.returncode == 1, f"STDERR: {result.stderr}"
        assert "Ansible playbook execution failed" in result.stderr

    def test_validation_failure_path(self, bash_helper):
        (bash_helper.temp_repo_path / "bin" / "kubectl").write_text("#!/bin/bash\nexit 1")
        result = bash_helper.run_bash_command("cluster_ops_upgrade_addons metallb")
        assert result.returncode == 1, f"STDERR: {result.stderr}"
        assert "Addon validation failed" in result.stderr

class TestClusterConfigureCoreDNS:
    def test_happy_path_with_args(self, bash_helper):
        result = bash_helper.run_bash_command("cluster_configure_coredns --dns-server 8.8.8.8 --domains example.com --yes")
        assert result.returncode == 0, f"STDERR: {result.stderr}"
        assert "CoreDNS configured successfully!" in result.stdout

    def test_dns_server_from_script(self, bash_helper):
        result = bash_helper.run_bash_command("cluster_configure_coredns --domains example.com --yes")
        assert result.returncode == 0, f"STDERR: {result.stderr}"
        assert "Found DNS server in Terraform: 1.1.1.1" in result.stderr

    def test_user_cancellation(self, bash_helper):
        (bash_helper.temp_repo_path / "lib" / "timeout.sh").write_text("#!/bin/bash\ntimeout_execute() { return 1; } # Simulate user saying 'n'")
        result = bash_helper.run_bash_command("cluster_configure_coredns")
        assert result.returncode == 0, f"STDERR: {result.stderr}"
        assert "Operation cancelled or timed out." in result.stdout

    def test_invalid_domain_format(self, bash_helper):
        # FIX: Use single quotes to pass the argument with a space correctly
        result = bash_helper.run_bash_command("cluster_configure_coredns --domains 'bad domain' --yes")
        assert result.returncode == 1, f"STDERR: {result.stderr}"
        assert "Invalid domains format" in result.stderr

class TestValidateAddonInstallation:
    def test_preflight_kubectl_missing(self, bash_helper):
        result = bash_helper.run_bash_command("PATH='' validate_addon_installation metallb")
        assert result.returncode == 1, f"STDERR: {result.stderr}"
        assert "kubectl command not found" in result.stderr

    def test_validate_metallb_success(self, bash_helper):
        result = bash_helper.run_bash_command("validate_addon_installation metallb")
        assert result.returncode == 0, f"STDERR: {result.stderr}"

    def test_validate_metrics_server_failure(self, bash_helper):
        (bash_helper.temp_repo_path / "bin" / "kubectl").write_text("#!/bin/bash\necho \"pod-456 Pending\"; exit 0")
        result = bash_helper.run_bash_command("validate_addon_installation metrics-server")
        assert result.returncode == 1, f"STDERR: {result.stderr}"
        assert "Metrics Server pods not ready" in result.stderr

    def test_unknown_addon(self, bash_helper):
        result = bash_helper.run_bash_command("validate_addon_installation unknown-addon")
        assert result.returncode == 1, f"STDERR: {result.stderr}"
        assert "Unknown addon for validation: unknown-addon" in result.stderr
