#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import yaml

def get_sops_decoded_secrets(secrets_file_path):
    """Decrypts the SOPS file and returns the data."""
    try:
        process = subprocess.run(
            ['sops', '-d', secrets_file_path],
            capture_output=True,
            text=True,
            check=True
        )
        return yaml.safe_load(process.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error decrypting SOPS file: {e}", file=sys.stderr)
        print(f"Stdout: {e.stdout}", file=sys.stderr)
        print(f"Stderr: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("Error: 'sops' command not found. Please ensure SOPS is installed and in your PATH.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred while handling SOPS file: {e}", file=sys.stderr)
        sys.exit(1)

def add_dns_record(pihole_ip, api_token, domain, ip_address):
    """Adds a DNS record to Pi-hole via its API."""
    if not pihole_ip or not api_token:
        print("Error: Pi-hole IP or API token is missing from secrets.", file=sys.stderr)
        return False

    # Construct the command
    command_parts = [
        'curl', '-s', '-X', 'POST',
        f"http://{pihole_ip}/admin/api.php",
        '--data-urlencode', f"addcustomdns",
        '--data-urlencode', f"ip={ip_address}",
        '--data-urlencode', f"domain={domain}",
        '--data-urlencode', f"auth={api_token}"
    ]

    # For printing, mask the API token
    masked_command_for_print = command_parts[:-1] + ['--data-urlencode', f"auth=***MASKED***"]
    print(f"Attempting to add DNS record: {domain} -> {ip_address} to Pi-hole at {pihole_ip}")
    print(f"Executing command: {' '.join(masked_command_for_print)}")

    try:
        result = subprocess.run(command_parts, capture_output=True, text=True, check=False) # check=False to handle API errors ourselves
        
        response_text = result.stdout.strip()
        print(f"Pi-hole API raw response: '{response_text}' (Return code: {result.returncode})")

        if result.returncode == 0:
            # Pi-hole success is typically an empty array [], empty object {}, or contains "success":true
            # It might also return nothing (empty string) on some versions/configurations for add.
            if response_text == "[]" or response_text == "{}" or response_text == "":
                print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (empty response interpreted as success)")
                return True
            try:
                response_json = json.loads(response_text)
                if isinstance(response_json, dict) and response_json.get("success") is True:
                    print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (API reported success: {response_json.get('message', '')})")
                    return True
                # Check for known error patterns if Pi-hole returns JSON with an error
                elif isinstance(response_json, dict) and response_json.get("error") is True:
                    print(f"Failed to add DNS record for {domain}. Pi-hole API error: {response_json.get('message', 'Unknown error')}", file=sys.stderr)
                    return False
                else:
                    print(f"Failed to add DNS record for {domain}. Unexpected JSON response: {response_text}", file=sys.stderr)
                    return False
            except json.JSONDecodeError:
                # If not empty and not valid JSON, it's likely an error page or unexpected output
                print(f"Failed to add DNS record for {domain}. Non-JSON response from Pi-hole: {response_text}", file=sys.stderr)
                return False
        else:
            print(f"Failed to add DNS record for {domain}. curl command failed. Status: {result.returncode}", file=sys.stderr)
            print(f"Curl Stdout: {result.stdout.strip()}", file=sys.stderr)
            print(f"Curl Stderr: {result.stderr.strip()}", file=sys.stderr)
            return False

    except subprocess.CalledProcessError as e: # Should not be hit if check=False, but good practice
        print(f"Error calling Pi-hole API for {domain}: {e}", file=sys.stderr)
        print(f"Stdout: {e.stdout}", file=sys.stderr)
        print(f"Stderr: {e.stderr}", file=sys.stderr)
        return False
    except FileNotFoundError:
        print("Error: 'curl' command not found. Please ensure curl is installed.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred during Pi-hole API call: {e}", file=sys.stderr)
        return False

def get_terraform_outputs(tf_dir):
    """Gets Terraform outputs, specifically vm_ipv4_addresses and vm_fqdns."""
    try:
        process = subprocess.run(
            ['tofu', 'output', '-json'],
            cwd=tf_dir,
            capture_output=True,
            text=True,
            check=True
        )
        outputs = json.loads(process.stdout)
        # Ensure the expected outputs exist and have the 'value' field
        vm_ips = outputs.get("vm_ipv4_addresses", {}).get("value", {})
        vm_fqdns = outputs.get("vm_fqdns", {}).get("value", {}) # Assuming you'll add this output
        
        if not vm_ips:
            print("Warning: 'vm_ipv4_addresses' output is empty or not found.", file=sys.stderr)
        if not vm_fqdns:
            print("Warning: 'vm_fqdns' output is empty or not found. Please add it to your Terraform outputs.", file=sys.stderr)
            print("Example for outputs.tf:", file=sys.stderr)
            print('''
output "vm_fqdns" {
  description = "FQDNs of the K8s VMs, mapped by their keys."
  value = {
    for k, vm_config in local.k8s_nodes : k => "${vm_config.role}${local.release_letter}${vm_config.index}${var.vm_domain}"
  }
}
            ''', file=sys.stderr)


        return vm_ips, vm_fqdns
    except subprocess.CalledProcessError as e:
        print(f"Error getting Terraform outputs: {e}", file=sys.stderr)
        print(f"Stdout: {e.stdout}", file=sys.stderr)
        print(f"Stderr: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("Error: 'tofu' command not found. Please ensure OpenTofu is installed and in your PATH.", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing Terraform output JSON: {e}", file=sys.stderr)
        print(f"Raw output: {process.stdout}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred while getting Terraform outputs: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Add DNS records from Terraform output to Pi-hole.")
    parser.add_argument(
        "--secrets-file",
        default="../terraform/secrets.sops.yaml", # Relative to the script's location
        help="Path to the SOPS encrypted secrets file."
    )
    parser.add_argument(
        "--tf-dir",
        default="../terraform", # Relative to the script's location
        help="Path to the Terraform configuration directory."
    )
    args = parser.parse_args()

    secrets = get_sops_decoded_secrets(args.secrets_file)
    # Adjust these keys based on the actual structure of your secrets.sops.yaml
    pihole_ip = secrets.get("pihole", {}).get("ip_address")
    api_token = secrets.get("pihole", {}).get("api_token")

    if not pihole_ip or not api_token:
        print("Error: Pi-hole IP or API token not found in secrets file.", file=sys.stderr)
        print(f"Ensure your {args.secrets_file} has a structure like:", file=sys.stderr)
        print('''
pihole:
  ip_address: "YOUR_PIHOLE_IP"
  api_token: "YOUR_PIHOLE_API_TOKEN"
# ... other secrets
''', file=sys.stderr)
        sys.exit(1)

    vm_ips, vm_fqdns = get_terraform_outputs(args.tf_dir)

    if not vm_ips or not vm_fqdns:
        print("Missing VM IPs or FQDNs from Terraform outputs. Cannot proceed.", file=sys.stderr)
        sys.exit(1)
        
    all_successful = True
    for vm_key, fqdn in vm_fqdns.items():
        ip_address = vm_ips.get(vm_key)
        if ip_address and fqdn: # Ensure both IP and FQDN are present
            if not add_dns_record(pihole_ip, api_token, fqdn, ip_address):
                all_successful = False
        else:
            print(f"Skipping DNS entry for {vm_key}: missing IP ({ip_address}) or FQDN ({fqdn}).", file=sys.stderr)
            all_successful = False
            
    if not all_successful:
        print("One or more DNS records failed to be added.", file=sys.stderr)
        sys.exit(1)
    else:
        print("All DNS records processed successfully.")

if __name__ == "__main__":
    main()
