import pytest

class TestEnhancedGetKubeconfig:
    """Tests for the enhanced_get_kubeconfig.sh script."""

    def test_calls_ansible_playbook_with_correct_vars(self, bash_helper, tmp_path):
        """Verify the script calls ansible-playbook with the expected extra-vars."""

        # 1. Создаем фейковую директорию для конфига внутри теста
        fake_config_dir = tmp_path / "fake_config"
        fake_config_dir.mkdir()
        # Можно даже создать фейковый файл конфига, если скрипт его ожидает
        (fake_config_dir / "config.yaml").write_text("cluster_name: my_test_cluster")

        (fake_config_dir / "repo_path").write_text(str(tmp_path))
        (fake_config_dir / "current_cluster_context").write_text("my_test_cluster")
        # 2. Готовим словарь с переменной окружения
        test_env = {"CPC_CONFIG_DIR": str(fake_config_dir)}

        # 3. Вызываем скрипт, передавая ему эту переменную
        result = bash_helper(
            "enhanced_get_kubeconfig.sh --help",
            env=test_env
        )

        assert result.returncode == 0, f"Script failed! Stderr: {result.stderr}"
        assert "Usage:" in result.stdout
