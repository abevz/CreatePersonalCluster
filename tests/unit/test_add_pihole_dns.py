import pytest
from unittest.mock import patch, MagicMock
import sys
from pathlib import Path
import json
import os

script_dir = Path(__file__).parent.parent.parent / "scripts"
sys.path.insert(0, str(script_dir))

import add_pihole_dns

class TestAddPiholeDns:
    """Test suite for the add_pihole_dns.py script."""

    @patch('os.path.exists', return_value=True)
    @patch('subprocess.run')
    @patch('add_pihole_dns.authenticate_pihole')
    def test_main_list_action(self, mock_auth, mock_subprocess, mock_exists, monkeypatch, capsys):
        """Test the 'list' action."""
        monkeypatch.setattr(sys, 'argv', ["", "--action", "list", "--tf-dir", "/fake", "--secrets-file", "/fake.yml"])
        
        mock_auth.return_value = {"sid": "test-sid", "csrf": "test-csrf"}

        mock_sops_result = MagicMock()
        mock_sops_result.stdout = """
default:
  pihole:
    ip_address: "1.1.1.1"
    web_password: "pw"
"""
        mock_sops_result.returncode = 0

        mock_curl_result = MagicMock()
        mock_curl_result.stdout = json.dumps([{"domain": "d.com", "ip": "1.2.3.4"}])
        mock_curl_result.returncode = 0

        mock_subprocess.side_effect = [mock_sops_result, mock_curl_result]

        with pytest.raises(SystemExit) as e:
            add_pihole_dns.main()
        
        assert e.value.code == 0
        captured = capsys.readouterr()
        assert "d.com -> 1.2.3.4" in captured.out