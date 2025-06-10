#!/usr/bin/env python3
import sys
import os
import subprocess
import json

def get_terraform_outputs(tf_dir, debug=True):
    """Test function to get terraform outputs"""
    try:
        if not os.path.isabs(tf_dir):
            script_dir = os.path.dirname(os.path.abspath(__file__))
            tf_dir = os.path.abspath(os.path.join(script_dir, tf_dir))

        print(f"DEBUG: Terraform directory: {tf_dir}")
        
        if not os.path.isdir(tf_dir):
            print(f"ERROR: Terraform directory not found: {tf_dir}")
            return False, f"Directory not found: {tf_dir}"

        command = ["tofu", "output", "-json"]
        print(f"DEBUG: Running command: {' '.join(command)} in {tf_dir}")

        process = subprocess.run(
            command,
            cwd=tf_dir,
            capture_output=True,
            text=True,
            check=False
        )

        print(f"DEBUG: Return code: {process.returncode}")
        if process.stderr:
            print(f"DEBUG: Stderr: {process.stderr.strip()}")

        if process.returncode != 0:
            return False, f"Command failed: {process.stderr.strip()}"
        
        if not process.stdout.strip():
            return False, "No output from command"

        try:
            outputs = json.loads(process.stdout)
            print(f"DEBUG: Successfully parsed JSON output")
            return True, outputs
        except json.JSONDecodeError as e:
            return False, f"JSON decode error: {e}"

    except Exception as e:
        return False, f"Unexpected error: {e}"

def main():
    tf_dir = "../terraform"
    
    print("Testing Terraform output extraction...")
    success, tf_outputs = get_terraform_outputs(tf_dir)
    
    if not success:
        print(f"Failed to get Terraform outputs: {tf_outputs}")
        sys.exit(1)
    
    print(f"Available outputs: {list(tf_outputs.keys())}")
    
    # Test the specific outputs we need
    k8s_node_ips = tf_outputs.get('k8s_node_ips', {}).get('value')
    k8s_node_names = tf_outputs.get('k8s_node_names', {}).get('value')
    
    print(f"k8s_node_ips: {k8s_node_ips} (type: {type(k8s_node_ips)})")
    print(f"k8s_node_names: {k8s_node_names} (type: {type(k8s_node_names)})")
    
    if not k8s_node_ips or not k8s_node_names:
        print("ERROR: One or both outputs are empty")
        sys.exit(1)
    
    if isinstance(k8s_node_ips, dict) and isinstance(k8s_node_names, dict):
        print("SUCCESS: Both outputs are dictionaries")
        print(f"IP keys: {sorted(list(k8s_node_ips.keys()))}")
        print(f"Name keys: {sorted(list(k8s_node_names.keys()))}")
        
        # Show the mapping
        for key in k8s_node_names.keys():
            fqdn = k8s_node_names.get(key)
            ip = k8s_node_ips.get(key)
            print(f"  {key}: {fqdn} -> {ip}")
    else:
        print(f"ERROR: Unexpected types - IPs: {type(k8s_node_ips)}, Names: {type(k8s_node_names)}")

if __name__ == "__main__":
    main()
