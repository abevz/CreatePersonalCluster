#!/usr/bin/env python

import json
import subprocess
import argparse

def get_terraform_output():
    # Run terraform output -json
    # This assumes you are in the terraform directory or have configured remote state
    try:
        # Adjust the path to your terraform project directory if needed
        # For example, if your terraform files are in a 'terraform' subdirectory:
        # result = subprocess.run(['terraform', 'output', '-json'], capture_output=True, text=True, check=True, cwd='../terraform')
        result = subprocess.run(['terraform', 'output', '-json'], capture_output=True, text=True, check=True, cwd='../terraform')
    except subprocess.CalledProcessError as e:
        print(f"Error running terraform output: {e}")
        return None
    except FileNotFoundError:
        print("Error: terraform command not found. Make sure Terraform is installed and in your PATH.")
        return None

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from terraform output: {e}")
        return None

def generate_inventory(tf_output):
    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "all": {
            "children": ["ungrouped"]
        },
        "ungrouped": {
            "hosts": []
        }
    }

    # Example: Assuming your terraform output includes IP addresses for VMs
    # You'll need to adjust this based on your actual terraform output structure
    # For instance, if you have an output variable named 'vm_ips' which is a map of vm_name to ip_address:
    # if 'vm_ips' in tf_output and tf_output['vm_ips']['value']:
    #     for vm_name, ip_address in tf_output['vm_ips']['value'].items():
    #         inventory["ungrouped"]["hosts"].append(ip_address)
    #         inventory["_meta"]["hostvars"][ip_address] = {
    #             "ansible_host": ip_address,
    #             "vm_name": vm_name
    #             # Add other host-specific variables here if needed
    #         }

    # Placeholder for actual logic based on your terraform outputs
    # You need to inspect your `terraform output` and adapt this script
    # For example, if you have an output 'instance_ips':
    if tf_output and 'instance_ips' in tf_output and tf_output['instance_ips']['value']:
        for name, ip in tf_output['instance_ips']['value'].items():
            inventory["ungrouped"]["hosts"].append(ip)
            inventory["_meta"]["hostvars"][ip] = {"ansible_host": ip}
    elif tf_output and 'kube_control_plane_ips' in tf_output and 'kube_worker_ips' in tf_output:
        control_plane_ips = tf_output['kube_control_plane_ips']['value']
        worker_ips = tf_output['kube_worker_ips']['value']

        inventory['all']['children'].extend(['control_plane', 'workers'])
        inventory['control_plane'] = {'hosts': []}
        inventory['workers'] = {'hosts': []}


        for name, ip in control_plane_ips.items():
            inventory['control_plane']['hosts'].append(ip)
            inventory['_meta']['hostvars'][ip] = {'ansible_host': ip, 'node_name': name}

        for name, ip in worker_ips.items():
            inventory['workers']['hosts'].append(ip)
            inventory['_meta']['hostvars'][ip] = {'ansible_host': ip, 'node_name': name}
        
        if not control_plane_ips and not worker_ips:
             inventory["ungrouped"]["hosts"].append("localhost") # Default if no IPs found
             inventory["_meta"]["hostvars"]["localhost"] = {"ansible_connection": "local"}


    else:
        # Default to localhost if no specific IP output is found
        # This is useful for initial testing or if VMs are not yet created
        inventory["ungrouped"]["hosts"].append("localhost")
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
