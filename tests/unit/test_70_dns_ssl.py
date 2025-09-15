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
            f"source {(self.temp_repo_path / 'modules/20_ansible.sh').resolve()}",
            f"source {(self.temp_repo_path / 'modules/70_dns_ssl.sh').resolve()}"
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
    bin_dir = repo_root / "bin"
    ansible_dir = repo_root / "ansible" / "playbooks"
    pki_dir = repo_root / "etc" / "kubernetes" / "pki"
    
    pki_dir.mkdir(parents=True, exist_ok=True)
    modules_dir.mkdir()
    lib_dir.mkdir()
    bin_dir.mkdir()
    ansible_dir.mkdir(parents=True)

    project_root = Path("/home/abevz/Projects/kubernetes/CreatePersonalCluster")
    shutil.copy(project_root / "modules/70_dns_ssl.sh", modules_dir)
    
    real_lib_path = project_root / "lib"
    for lib_file in real_lib_path.glob("*.sh"):
        shutil.copy(lib_file, lib_dir)

    core_mock_content = """#!/bin/bash
export REPO_ROOT='{repo_root}'
export SCRIPT_DIR='{script_dir}'
source \"{logging_sh}\"
source \"{error_handling_sh}\" 
""".format(
        repo_root=str(repo_root),
        script_dir=str(repo_root),
        logging_sh=str(lib_dir / 'logging.sh'),
        error_handling_sh=str(lib_dir / 'error_handling.sh')
    )
    (modules_dir / "00_core.sh").write_text(core_mock_content)

    (modules_dir / "20_ansible.sh").write_text("""
        #!/bin/bash
        ansible_run_playbook() {
            echo "Mock ansible_run_playbook called with: $@"
            if [[ \"$FORCE_ANSIBLE_FAILURE\" == \"true\" ]]; then return 1; fi
            return 0
        }
    """)
    (ansible_dir / "regenerate_certificates_with_dns.yml").touch()

    (bin_dir / "kubectl").write_text("""
        #!/bin/bash
        if [[ \"$1\" == \"cluster-info\" && \"$FORCE_KUBECTL_FAILURE\" == \"true\" ]]; then exit 1; fi
        if [[ \"$1\" == \"run\" ]]; then
            if [[ \"$*\" == *\"--image=busybox\"* && \"$FORCE_KUBECTL_RUN_FAILURE\" == \"true\" ]]; then
                echo "Mock kubectl run error"
                exit 1
            fi
            echo "Server: 1.1.1.1"
            echo "Address: 1.1.1.1#53"
            exit 0
        fi
        if [[ \"$1\" == \"get\" && \"$2\" == \"pods\" ]]; then
             echo "coredns-123   1/1     Running   0          2m"
             echo "coredns-456   1/1     Running   0          2m"
             exit 0
        fi
        if [[ \"$1\" == \"get\" && \"$2\" == \"configmap\" ]]; then
            echo 'Corefile data here...'
            exit 0
        fi
        exit 0
    """)
    (bin_dir / "kubectl").chmod(0o755)

    (bin_dir / "openssl").write_text("""
        #!/bin/bash
        if [[ \"$1\" == \"x509\" && ! -s \"$3\" ]]; then exit 1; fi
        if [[ \"$*\" == *\"-enddate\"* ]]; then echo \"notAfter=Jan 1 00:00:00 2030 GMT\"; fi
        if [[ \"$*\" == *\"-checkend\"* ]]; then
            if [[ \"$FORCE_OPENSSL_EXPIRE\" == \"true\" ]]; then exit 1; else exit 0; fi
        fi
        if [[ \"$*\" == *\"-text\"* ]]; then
            echo "Subject Alternative Name:"
            echo "    DNS:kubernetes, DNS:kubernetes.default"
            echo "    IP Address:10.96.0.1"
        fi
        exit 0
    """)
    (bin_dir / "openssl").chmod(0o755)
    
    (pki_dir / "apiserver.crt").write_text("-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----")
    (pki_dir / "apiserver-kubelet-client.crt").write_text("-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----")

    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ.get("PATH", ""))
    
    return repo_root

@pytest.fixture(scope="function")
def bash_helper(temp_repo: Path) -> BashTestHelper:
    return BashTestHelper(temp_repo)

# --- Test Classes ---

class TestDnsSslRegenerateCertificates:
    def test_get_target_node_interactive(self, bash_helper):
        result = bash_helper.run_bash_command("_regenerate_get_target_node", input_text="1\n")
        assert result.returncode == 0
        assert "control_plane[0]" in result.stdout

    def test_full_workflow_cancelled(self, bash_helper):
        result = bash_helper.run_bash_command("dns_ssl_regenerate_certificates my-node-1", input_text="no\n")
        assert result.returncode == 1
        assert "Certificate regeneration cancelled by user" in result.stdout

class TestDnsSslTestResolution:
    def test_preflight_checks_failure(self, bash_helper):
        result = bash_helper.run_bash_command("_test_dns_preflight_checks", env={"FORCE_KUBECTL_FAILURE": "true"})
        assert result.returncode == 1
        assert "Cannot connect to Kubernetes cluster" in result.stdout

    def test_run_main_test_success(self, bash_helper):
        result = bash_helper.run_bash_command("_test_dns_run_main_test google.com")
        assert result.returncode == 0
        assert "DNS test successful!" in result.stdout

    def test_run_main_test_failure(self, bash_helper):
        result = bash_helper.run_bash_command("_test_dns_run_main_test google.com", env={"FORCE_KUBECTL_RUN_FAILURE": "true"})
        assert result.returncode == 1
        assert "DNS test failed!" in result.stdout

class TestDnsSslVerifyCertificates:
    def test_verify_single_local_cert_valid(self, bash_helper, temp_repo):
        cert_path = temp_repo / "etc/kubernetes/pki/apiserver.crt"
        result = bash_helper.run_bash_command(f"_verify_single_local_cert {cert_path} 'API Server'")
        assert result.returncode == 0
        assert "Status: ✅ Valid" in result.stdout

    def test_verify_single_local_cert_expired(self, bash_helper, temp_repo):
        cert_path = temp_repo / "etc/kubernetes/pki/apiserver.crt"
        result = bash_helper.run_bash_command(f"_verify_single_local_cert {cert_path} 'API Server'", env={"FORCE_OPENSSL_EXPIRE": "true"})
        assert result.returncode == 0
        assert "Status: ❌ Expired" in result.stdout
        assert "Certificate expired" in result.stdout

    def test_verify_single_local_cert_not_found(self, bash_helper):
        result = bash_helper.run_bash_command("_verify_single_local_cert /no/such/file.crt 'Fake Cert'")
        assert result.returncode == 0
        assert "Certificate file not found" in result.stdout

    def test_verify_certs_remotely_failure(self, bash_helper):
        result = bash_helper.run_bash_command("_verify_certs_remotely", env={"FORCE_KUBECTL_FAILURE": "true"})
        assert result.returncode == 0
        assert "Cannot connect to cluster" in result.stdout

class TestDnsSslCheckClusterDns:
    def test_preflight_failure(self, bash_helper):
        result = bash_helper.run_bash_command("_check_dns_preflight", env={"FORCE_KUBECTL_FAILURE": "true"})
        assert result.returncode == 1
        assert "Cannot connect to Kubernetes cluster" in result.stdout

    def test_get_pod_status(self, bash_helper):
        result = bash_helper.run_bash_command("_check_dns_get_pod_status")
        assert result.returncode == 0
        assert "coredns-123" in result.stdout

    def test_full_check_workflow(self, bash_helper):
        result = bash_helper.run_bash_command("dns_ssl_check_cluster_dns")
        assert result.returncode == 0
        assert "Cluster DNS check completed!" in result.stdout
