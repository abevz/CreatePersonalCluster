import pytest
from pathlib import Path

class TestSshUtils:
    """Tests for functions in ssh_utils.sh."""
    def test_ssh_clear_known_hosts_calls_ssh_keygen(self, bash_helper, tmp_path):
        """
        Verify that ssh_clear_known_hosts calls ssh-keygen -R with the correct pattern.
        """
        # 1. Создаем фейковый файл known_hosts во временной директории
        fake_known_hosts = tmp_path / "known_hosts"
        fake_known_hosts.write_text("some-host ssh-rsa AAAA...")

        # 2. Готовим окружение, чтобы указать скрипту, где искать этот файл
        test_env = {"SSH_KNOWN_HOSTS_FILE": str(fake_known_hosts)}

        # 3. Вызываем функцию, передавая ей наше кастомное окружение
        result = bash_helper(
            'ssh_clear_known_hosts "my-host-pattern"',
            env=test_env
        )

        # 4. Теперь все проверки должны пройти
        assert result.returncode == 0, f"Script failed! Stderr: {result.stderr}"

        ssh_keygen_log = tmp_path / "ssh-keygen.log"
        assert ssh_keygen_log.exists(), "Mock for ssh-keygen was not called!"

        log_content = ssh_keygen_log.read_text()
        assert "-R my-host-pattern" in log_content

    def test_ssh_test_connection_calls_ssh_with_correct_flags(self, bash_helper, tmp_path):
        """
        Verify that ssh_test_connection calls ssh with the correct flags.
        """
        result = bash_helper('ssh_test_connection "my-host" "my-user" "10"')

        assert result.returncode == 0

        ssh_log = tmp_path / "ssh.log"
        assert ssh_log.exists()

        log_content = ssh_log.read_text()
        assert "-o ConnectTimeout=10" in log_content
        assert "-o BatchMode=yes" in log_content
        assert "my-user@my-host" in log_content
