#!/usr/bin/env python

import json
import subprocess
import argparse

def get_terraform_output():
    # Run tofu output -json (using OpenTofu instead of Terraform)
    import os
    # Get the parent directory of the ansible directory, then go to terraform
    terraform_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'terraform')
    try:
        result = subprocess.run(['tofu', 'output', '-json'], capture_output=True, text=True, check=True, cwd=terraform_dir)
    except subprocess.CalledProcessError as e:
        print(f"Error running tofu output: {e}")
        return None
    except FileNotFoundError:
        print("Error: tofu command not found. Make sure OpenTofu is installed and in your PATH.")
        return None

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from tofu output: {e}")
        return None

def generate_inventory(tf_output):
    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "all": {
            "children": ["control_plane", "workers"]
        },
        "control_plane": {
            "hosts": []
        },
        "workers": {
            "hosts": []
        }
    }

    if not tf_output:
        # Default to localhost if no tofu output is found
        inventory["all"]["children"] = ["ungrouped"]
        inventory["ungrouped"] = {"hosts": ["localhost"]}
        inventory["_meta"]["hostvars"]["localhost"] = {"ansible_connection": "local"}
        return inventory

    # Parse the k8s_node_ips and debug_node_configs outputs from tofu
    if 'k8s_node_ips' in tf_output and 'debug_node_configs' in tf_output:
        node_ips = tf_output['k8s_node_ips']['value']
        node_configs = tf_output['debug_node_configs']['value']
        node_names = tf_output.get('k8s_node_names', {}).get('value', {})

        for node_key, ip_address in node_ips.items():
            if node_key in node_configs:
                node_config = node_configs[node_key]
                role = node_config.get('role', 'w')  # default to worker
                hostname = node_config.get('hostname', node_key)
                
                # Determine group based on role
                if role == 'c':  # control plane
                    inventory['control_plane']['hosts'].append(ip_address)
                else:  # worker
                    inventory['workers']['hosts'].append(ip_address)
                
                # Set host variables
                inventory['_meta']['hostvars'][ip_address] = {
                    'ansible_host': ip_address,
                    'node_name': node_key,
                    'hostname': hostname,
                    'k8s_role': 'control-plane' if role == 'c' else 'worker',
                    'vm_id': node_config.get('vm_id')
                }

    # Remove empty groups
    if not inventory['control_plane']['hosts']:
        inventory['all']['children'].remove('control_plane')
        del inventory['control_plane']
    if not inventory['workers']['hosts']:
        inventory['all']['children'].remove('workers')
        del inventory['workers']

    # If no groups have hosts, add localhost as fallback
    if not any(group in inventory for group in ['control_plane', 'workers']):
        inventory["all"]["children"] = ["ungrouped"]
        inventory["ungrouped"] = {"hosts": ["localhost"]}
        inventory["_meta"]["hostvars"]["localhost"] = {"ansible_connection": "local"}

    return inventory

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--host', action='store')
    args = parser.parse_args()

    tf_output = get_terraform_output()
    inventory = generate_inventory(tf_output)

    if args.list:
        print(json.dumps(inventory, indent=4))
    elif args.host:
        # Not strictly necessary for basic use, but good practice
        print(json.dumps(inventory["_meta"]["hostvars"].get(args.host, {}), indent=4))
    else:
        print(json.dumps(inventory, indent=4))

if __name__ == "__main__":
    main()
