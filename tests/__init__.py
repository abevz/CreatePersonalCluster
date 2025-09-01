#!/usr/bin/env python3
"""
Test framework for CPC (Create Personal Cluster) project
"""

import os
import sys
import subprocess
import pytest
from pathlib import Path

class TestFramework:
    """Base test framework for CPC testing"""

    def __init__(self):
        self.project_root = Path(__file__).parent.parent

    @staticmethod
    def run_command(cmd, cwd=None, env=None):
        """Run shell command and return result"""
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                cwd=cwd or Path(__file__).parent.parent,
                env=env,
                capture_output=True,
                text=True,
                timeout=30
            )
            return result
        except subprocess.TimeoutExpired:
            return None
        except Exception as e:
            print(f"Command failed: {e}")
            return None

    @staticmethod
    def check_file_exists(filepath):
        """Check if file exists"""
        return Path(Path(__file__).parent.parent / filepath).exists()

    @staticmethod
    def read_file(filepath):
        """Read file content"""
        try:
            return Path(Path(__file__).parent.parent / filepath).read_text()
        except Exception:
            return None

# Export for use in tests
test_framework = TestFramework()
