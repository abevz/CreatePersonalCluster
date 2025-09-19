import pytest
from unittest.mock import patch, MagicMock
import sys
from pathlib import Path
import json

script_dir = Path("/home/abevz/Projects/kubernetes/CreatePersonalCluster/scripts")
sys.path.insert(0, str(script_dir))

import test_terraform_outputs

class TestTerraformOutputsScript:
    """Test suite for the test_terraform_outputs.py script."""

    @patch('subprocess.run')
    def test_main_success(self, mock_subprocess, capsys):
        """Test the main function with a valid mocked tofu output."""
        
        # Mock the JSON output from 'tofu output -json'
        mock_output = {
            "k8s_node_ips": {"value": {"node1": "1.1.1.1"}},
            "k8s_node_names": {"value": {"node1": "node1.example.com"}}
        }
        mock_result = MagicMock()
        mock_result.stdout = json.dumps(mock_output)
        mock_result.returncode = 0
        mock_subprocess.return_value = mock_result

        # Mock os.path.isdir to avoid filesystem dependency
        with patch('os.path.isdir', return_value=True):
            test_terraform_outputs.main()

        captured = capsys.readouterr()
        assert "SUCCESS: Both outputs are dictionaries" in captured.out
        assert "node1.example.com -> 1.1.1.1" in captured.out

    @patch('subprocess.run')
    def test_main_failure_on_command_error(self, mock_subprocess, capsys):
        """Test the main function when the tofu command fails."""
        
        mock_result = MagicMock()
        mock_result.stderr = "tofu command failed"
        mock_result.returncode = 1
        mock_subprocess.return_value = mock_result

        with patch('os.path.isdir', return_value=True):
            with pytest.raises(SystemExit) as e:
                test_terraform_outputs.main()
        
        assert e.value.code == 1
        captured = capsys.readouterr()
        assert "Failed to get Terraform outputs" in captured.out
