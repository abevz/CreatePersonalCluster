# tests/conftest.py
import pytest
from pathlib import Path
import subprocess
import os
import shutil

@pytest.fixture
def bash_helper(tmp_path: Path, monkeypatch):
    """
    A master fixture to provide a helper for running bash script functions
    in a fully mocked and isolated environment.
    """
    repo_root = tmp_path
    lib_dir = repo_root / "lib"
    bin_dir = repo_root / "bin"

    for d in [lib_dir, bin_dir]:
        d.mkdir(exist_ok=True)

    # --- Dynamically find project root ---
    PROJECT_ROOT = Path(__file__).parent.parent

    print(f"\nDEBUG: Project root determined to be: {PROJECT_ROOT}")

    # Copy real library scripts to be sourced
    lib_source_dir = PROJECT_ROOT / "lib"
    if lib_source_dir.exists():
        for script in lib_source_dir.glob("*.sh"):
            shutil.copy(script, lib_dir)

    # ВАЖНО: Этот блок копирует исполняемые скрипты из папки /scripts
    # Copy real executable scripts to the mock bin directory
    scripts_source_dir = PROJECT_ROOT / "scripts"
    
    print(f"DEBUG: Checking for scripts directory at: {scripts_source_dir}")

    if scripts_source_dir.exists():
        print("DEBUG: Scripts directory FOUND. Starting to copy...")
        for script in scripts_source_dir.glob("*.sh"):
            print(f"DEBUG:   - Copying {script.name}")
            dest_script = bin_dir / script.name
            shutil.copy(script, dest_script)
            dest_script.chmod(0o755) # Делаем их исполняемыми
    else:
        print("DEBUG: Scripts directory NOT FOUND. Skipping copy of executables.")
    # Create smarter mocks that log their arguments
    mock_commands = ["curl", "ssh", "scp", "tofu", "id", "command", "ansible-playbook", "ssh-keygen"]
    for cmd in mock_commands:
        mock_path = bin_dir / cmd
        log_file = tmp_path / f"{cmd}.log"
        # Мок будет записывать все свои аргументы в лог-файл
        mock_path.write_text(f"#!/bin/bash\necho \"$@\" >> {log_file}")
        mock_path.chmod(0o755)

    # Prepend our mock bin directory to the PATH
    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ.get("PATH", ""))

    def run_command(command: str, env: dict = None):
        # 1. Всегда начинаем с полной, измененной monkeypatch'ем копии окружения
        full_env = os.environ.copy()

        # 2. Если тест передал свои переменные, добавляем или обновляем их
        if env is not None:
            full_env.update(env)

        # Добавляем наш REPO_PATH, как и раньше
        full_env["REPO_PATH"] = str(repo_root)

        sourcing_script = ""
        for lib in sorted(lib_dir.glob("*.sh")):
            sourcing_script += f'source "{lib}" || {{ echo "FATAL: Failed to source {lib.name}" >&2; exit 1; }}\n'

        full_command = f"""
        set -e
        {sourcing_script}
        {command}
        """

        return subprocess.run(
            ['bash', '-c', full_command],
            capture_output=True,
            text=True,
            # 3. Используем объединенное окружение
            env=full_env
        )
    return run_command

