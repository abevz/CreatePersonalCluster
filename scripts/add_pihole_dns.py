#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import yaml
import urllib.parse
import os
import requests

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

def authenticate_pihole(pihole_ip, web_password):
    """Authenticates to Pi-hole and returns session ID (SID) and CSRF token."""
    auth_url = f"http://{pihole_ip}/api/auth"
    payload = {"password": web_password}
    headers = {"Content-Type": "application/json"} # Add Content-Type header
    print(f"Attempting to authenticate to Pi-hole at {pihole_ip} with JSON payload.")
    try:
        # Send payload as JSON
        response = requests.post(auth_url, data=json.dumps(payload), headers=headers, timeout=10)
        response.raise_for_status() # Raise an exception for bad status codes
        
        data = response.json()
        if data.get("session") and data["session"].get("valid") is True:
            sid = data["session"].get("sid")
            csrf_token = data["session"].get("csrf")
            if sid and csrf_token:
                print("Authentication successful. SID and CSRF token obtained.")
                return {"sid": sid, "csrf": csrf_token}
            else:
                print(f"Authentication succeeded but SID or CSRF token missing in response: {data}")
                return None
        else:
            print(f"Authentication failed. Response: {data}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error during Pi-hole authentication: {e}")
        # If the error is an HTTPError, print the response content for more details
        if isinstance(e, requests.exceptions.HTTPError) and e.response is not None:
            print(f"Pi-hole auth error response: {e.response.status_code} - {e.response.text}")
        return None
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from Pi-hole authentication response: {e}. Response text: {response.text}")
        return None

def add_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=False):
    """Adds a DNS record to Pi-hole via its API using PUT /api/config/dns/hosts/."""
    
    encoded_entry = urllib.parse.quote(f"{ip_address} {domain}")
    api_url = f"http://{pihole_ip}/api/config/dns/hosts/{encoded_entry}"

    command_parts = [
        'curl', '-s', '-X', 'PUT',
        '-H', "Content-Type: application/json",
        '-H', f"X-CSRF-Token: {csrf_token}",
        '--cookie', f"SID={sid}",
        api_url
    ]
    
    if debug:
        print(f"DEBUG_COMMAND: {' '.join(command_parts)}")

    print(f"Attempting to add/update DNS record: {domain} -> {ip_address}")

    try:
        result = subprocess.run(command_parts, capture_output=True, text=True, check=False)
        response_text = result.stdout.strip()
        print(f"Pi-hole DNS API raw response: '{response_text}' (Return code: {result.returncode})")

        if result.returncode == 0: # curl command executed successfully
            if not response_text: # Truly empty response
                print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (empty response interpreted as success)")
                return True
            
            try:
                response_json = json.loads(response_text)
                if not isinstance(response_json, dict):
                    # If it's JSON but not a dictionary, it's unexpected.
                    print(f"Failed to add DNS record for {domain}. Unexpected JSON type (expected dict, got {type(response_json).__name__}): {response_text}", file=sys.stderr)
                    return False

                # Now we know response_json is a dictionary
                if response_json.get("success") is True:
                    message = response_json.get("message", "Action successful.") # Provide a default message
                    print(f"Successfully added/updated DNS record for {domain} -> {ip_address}. Pi-hole message: {message}")
                    return True
                elif "error" in response_json:
                    error_details = response_json.get("error", {})
                    error_message = error_details.get("message", "Unknown error")
                    if isinstance(error_details, dict):
                         hint = error_details.get("hint", "")
                         key = error_details.get("key", "N/A")
                         error_message = f"{key}: {error_message}. Hint: {hint}"
                    print(f"Failed to add DNS record for {domain}. Pi-hole API error: {error_message}", file=sys.stderr)
                    return False
                elif "took" in response_json: # This is the observed success case from user logs
                    print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (API reported 'took': {response_json.get('took')}, interpreted as success)")
                    return True
                elif response_text == "{}": # Empty JSON object, sometimes used for success
                    print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (empty JSON object '{{}}' interpreted as success)")
                    return True
                else:
                    # JSON dictionary, but not matching known success/error patterns
                    print(f"Failed to add DNS record for {domain}. Unexpected JSON dictionary content: {response_text}", file=sys.stderr)
                    return False

            except json.JSONDecodeError:
                # Non-JSON response (and not empty, as that's handled above)
                print(f"Failed to add DNS record for {domain}. Non-JSON response from Pi-hole: {response_text}", file=sys.stderr)
                return False
        else: # curl command itself failed
            print(f"Failed to add DNS record for {domain}. curl command failed. Status: {result.returncode}", file=sys.stderr)
            print(f"Curl Stdout: {result.stdout.strip()}", file=sys.stderr)
            print(f"Curl Stderr: {result.stderr.strip()}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"An unexpected error occurred during Pi-hole DNS API call: {e}", file=sys.stderr)
        return False

def delete_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=False):
    """Deletes a DNS record from Pi-hole via its API using DELETE /api/config/dns/hosts/."""
    
    encoded_entry = urllib.parse.quote(f"{ip_address} {domain}")
    api_url = f"http://{pihole_ip}/api/config/dns/hosts/{encoded_entry}"

    command_parts = [
        'curl', '-s', '-X', 'DELETE',
        '-H', "Content-Type: application/json", # Though not strictly needed for DELETE with no body
        '-H', f"X-CSRF-Token: {csrf_token}",
        '--cookie', f"SID={sid}",
        api_url
    ]
    
    if debug:
        print(f"DEBUG_COMMAND: {' '.join(command_parts)}")

    print(f"Attempting to delete DNS record: {domain} -> {ip_address}")
    # print(f"Executing command: {' '.join(command_parts)}") # Avoid printing tokens/sid

    try:
        result = subprocess.run(command_parts, capture_output=True, text=True, check=False)
        response_text = result.stdout.strip()
        print(f"Pi-hole DNS API raw response (delete): '{response_text}' (Return code: {result.returncode})")

        if result.returncode == 0: # curl command executed successfully
            if not response_text: # Empty response is often success for DELETE
                print(f"Successfully deleted DNS record for {domain} -> {ip_address} (empty response interpreted as success)")
                return True
            
            try:
                response_json = json.loads(response_text)
                if not isinstance(response_json, dict):
                    print(f"Failed to delete DNS record for {domain}. Unexpected JSON type (expected dict, got {type(response_json).__name__}): {response_text}", file=sys.stderr)
                    return False

                if response_json.get("success") is True:
                    message = response_json.get("message", "Action successful.")
                    print(f"Successfully deleted DNS record for {domain} -> {ip_address}. Pi-hole message: {message}")
                    return True
                elif "error" in response_json:
                    error_details = response_json.get("error", {})
                    error_message = error_details.get("message", "Unknown error")
                    if isinstance(error_details, dict):
                         hint = error_details.get("hint", "")
                         key = error_details.get("key", "N/A")
                         error_message = f"{key}: {error_message}. Hint: {hint}"
                    print(f"Failed to delete DNS record for {domain}. Pi-hole API error: {error_message}", file=sys.stderr)
                    return False
                # Pi-hole might return something like {"message": "Deleted ..."} without a top-level "success" key
                # or just {"took": ...} as observed for add. For delete, an empty response is common.
                # Let's assume if no error and it's a dict, it might be a custom success message.
                # The primary check for delete is often an empty body and 200/204 status.
                # Since curl -s hides status, we rely on returncode 0 and parseable/empty response.
                elif response_text == "{}": # Empty JSON object
                    print(f"Successfully deleted DNS record for {domain} -> {ip_address} (empty JSON object '{{}}' interpreted as success)")
                    return True
                else:
                    # If it's a dict but doesn't match known patterns, treat as unexpected for now.
                    # It could be a success message like {"message": "Record deleted"} without a success flag.
                    # For now, being conservative. If Pi-hole returns such a message, this can be refined.
                    print(f"Deleted DNS record for {domain} -> {ip_address} (response interpreted as informational, assuming success if no error: {response_text})")
                    return True # Assuming if no error and some JSON, it might be okay for delete.

            except json.JSONDecodeError:
                print(f"Failed to delete DNS record for {domain}. Non-JSON response from Pi-hole: {response_text}", file=sys.stderr)
                return False
        else: # curl command itself failed
            print(f"Failed to delete DNS record for {domain}. curl command failed. Status: {result.returncode}", file=sys.stderr)
            print(f"Curl Stdout: {result.stdout.strip()}", file=sys.stderr)
            print(f"Curl Stderr: {result.stderr.strip()}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"An unexpected error occurred during Pi-hole DNS API call (delete): {e}", file=sys.stderr)
        return False

def get_terraform_outputs(tf_dir, debug=False): # Add debug parameter
    """Runs 'tofu output -json' in the specified directory and returns the parsed JSON."""
    try:
        # Ensure tf_dir is an absolute path
        if not os.path.isabs(tf_dir):
            script_dir = os.path.dirname(os.path.abspath(__file__))
            tf_dir = os.path.abspath(os.path.join(script_dir, tf_dir))

        if debug: print(f"DEBUG: [get_terraform_outputs] Terraform directory: {tf_dir}") # Conditional print
        
        # Check if the Terraform directory exists
        if not os.path.isdir(tf_dir):
            error_msg = f"Terraform directory not found: {tf_dir}"
            print(f"ERROR: [get_terraform_outputs] {error_msg}")
            return False, error_msg

        # Check for .terraform directory and terraform.tfstate
        if not os.path.exists(os.path.join(tf_dir, ".terraform")):
            # error_msg = f".terraform directory not found in {tf_dir}. Make sure to run 'terraform init'." # Original
            # if debug: print(f"DEBUG: [get_terraform_outputs] {error_msg}") # Conditional print for the original message
            pass # Allow tofu to report this error
        if not os.path.exists(os.path.join(tf_dir, "terraform.tfstate")):
            # error_msg = f"terraform.tfstate not found in {tf_dir}. Make sure to run 'terraform apply'." # Original
            # if debug: print(f"DEBUG: [get_terraform_outputs] {error_msg}") # Conditional print for the original message
            pass # Allow tofu to report this error

        command = ["tofu", "output", "-json"]
        if debug: print(f"DEBUG: [get_terraform_outputs] Running command: {' '.join(command)} in {tf_dir}") # Conditional print

        process = subprocess.run(
            command,
            cwd=tf_dir,      # Run the command in the Terraform directory
            capture_output=True,
            text=True,
            check=False      # Set to False to inspect output even on error
        )

        if debug: # Conditional block for multiple prints
            print(f"DEBUG: [get_terraform_outputs] tofu command return code: {process.returncode}")
            print(f"DEBUG: [get_terraform_outputs] tofu command stdout: {process.stdout.strip()[:500]}...") # Print first 500 chars
            if process.stderr:
                print(f"DEBUG: [get_terraform_outputs] tofu command stderr: {process.stderr.strip()}")

        if process.returncode != 0:
            error_msg = f"Error running 'tofu output -json'. Return code: {process.returncode}. Stderr: {process.stderr.strip()}"
            print(f"ERROR: [get_terraform_outputs] {error_msg}")
            return False, error_msg
        
        if not process.stdout.strip():
            error_msg = "'tofu output -json' produced no output."
            print(f"ERROR: [get_terraform_outputs] {error_msg}")
            return False, error_msg

        try:
            outputs = json.loads(process.stdout)
            if debug: print(f"DEBUG: [get_terraform_outputs] Successfully parsed JSON output.") # Conditional print
            return True, outputs
        except json.JSONDecodeError as e:
            error_msg = f"Failed to decode JSON from tofu output: {e}. Output was: {process.stdout.strip()[:500]}..."
            print(f"ERROR: [get_terraform_outputs] {error_msg}")
            return False, error_msg

    except Exception as e:
        error_msg = f"An unexpected error occurred in get_terraform_outputs: {e}"
        print(f"ERROR: [get_terraform_outputs] {error_msg}")
        return False, error_msg

def load_sops_secrets(custom_secrets_file_path=None, debug=False): # Add debug parameter
    """Loads secrets from the SOPS file.
    Uses custom_secrets_file_path if provided, otherwise defaults to
    ../terraform/secrets.sops.yaml relative to this script.
    """
    sops_file_to_use = None
    if custom_secrets_file_path:
        sops_file_to_use = custom_secrets_file_path
        # Ensure the provided path is absolute, as cpc provides it this way.
        # If a user provides a relative path, it will be resolved relative to CWD.
        if not os.path.isabs(sops_file_to_use):
            if debug: print(f"DEBUG: Provided secrets file path '{sops_file_to_use}' is not absolute. Resolving against CWD '{os.getcwd()}'.") # Conditional print
            sops_file_to_use = os.path.abspath(sops_file_to_use)
        if debug: print(f"DEBUG: Using SOPS secrets file provided via argument: {sops_file_to_use}") # Conditional print
    else:
        try:
            script_path = os.path.abspath(__file__)
            script_dir = os.path.dirname(script_path)
            default_sops_path = os.path.abspath(os.path.join(script_dir, "..", "terraform", "secrets.sops.yaml"))
            sops_file_to_use = default_sops_path
            if debug: print(f"DEBUG: Using default SOPS secrets file: {sops_file_to_use}") # Conditional print
        except Exception as e:
            print(f"Error determining default SOPS file path: {e}", file=sys.stderr)
            sys.exit(1)

    if not os.path.exists(sops_file_to_use):
        print(f"Error: SOPS secrets file not found at {sops_file_to_use}", file=sys.stderr)
        sys.exit(1)
    
    return get_sops_decoded_secrets(sops_file_to_use)

def main():
    parser = argparse.ArgumentParser(description="Manage Pi-hole DNS records based on Terraform outputs.")
    parser.add_argument(
        "--action",
        choices=['add', 'unregister-dns'], # Changed 'delete' to 'unregister-dns'
        required=True,
        help="Action to perform: 'add' or 'unregister-dns' DNS records."
    )
    parser.add_argument(
        "--tf-dir",
        required=True,
        help="Path to the Terraform directory containing outputs.tf and potentially .tfvars files."
    )
    parser.add_argument(
        "--secrets-file",
        help="Path to the SOPS-encrypted secrets YAML file. Defaults to ../terraform/secrets.sops.yaml relative to this script."
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug mode (prints curl commands and other debug info)."
    )

    args = parser.parse_args()

    if args.debug:
        print(f"DEBUG: Script arguments: {args}")

    # Load secrets
    secrets = load_sops_secrets(args.secrets_file, debug=args.debug) # Pass debug flag
    if not secrets:
        sys.exit(1)

    # Correctly access nested Pi-hole credentials
    pihole_ip = secrets.get('pihole', {}).get('ip_address')
    pihole_web_password = secrets.get('pihole', {}).get('web_password')

    if not pihole_ip or not pihole_web_password:
        print("Error: Pi-hole IP address or web password not found in secrets file under the 'pihole' key.", file=sys.stderr)
        if args.debug: # Conditional print
            print(f"DEBUG: Loaded secrets structure: {secrets}")
        sys.exit(1)

    # Authenticate to Pi-hole
    auth_details = authenticate_pihole(pihole_ip, pihole_web_password)
    if not auth_details:
        print("Failed to authenticate with Pi-hole. Exiting.", file=sys.stderr)
        sys.exit(1)
    
    sid = auth_details["sid"]
    csrf_token = auth_details["csrf"]

    # Get Terraform outputs
    success, tf_outputs = get_terraform_outputs(args.tf_dir, debug=args.debug) # Pass debug flag
    if not success:
        print(f"Failed to get Terraform outputs: {tf_outputs}", file=sys.stderr)
        sys.exit(1)

    if args.debug: # Conditional print
        print(f"DEBUG: Terraform outputs: {json.dumps(tf_outputs, indent=2)}")

    vm_ipv4_addresses_output = tf_outputs.get('k8s_node_ips', {}).get('value')
    vm_fqdns_output = tf_outputs.get('k8s_node_names', {}).get('value')

    if args.debug:
        print(f"DEBUG: Extracted vm_ipv4_addresses_output: {vm_ipv4_addresses_output} (type: {type(vm_ipv4_addresses_output)})")
        print(f"DEBUG: Extracted vm_fqdns_output: {vm_fqdns_output} (type: {type(vm_fqdns_output)})")

    if not vm_ipv4_addresses_output or not vm_fqdns_output:
        print("Error: vm_ipv4_addresses_output or vm_fqdns_output is empty after extracting from Terraform output.")
        sys.exit(1)
    
    # Handle both list and dict types for outputs
    # If they are dicts, we assume keys match between FQDNs and IPs
    records_to_process = []

    if isinstance(vm_fqdns_output, dict) and isinstance(vm_ipv4_addresses_output, dict):
        if args.debug:
            print(f"DEBUG: Processing FQDNs and IPs as dictionaries. Matching based on shared keys.")
        
        # Ensure the dictionaries have the same set of keys for reliable matching
        if set(vm_fqdns_output.keys()) != set(vm_ipv4_addresses_output.keys()):
            print("Warning: Keys in vm_fqdns_output and vm_ipv4_addresses_output do not match. This may lead to incorrect DNS entries.")
            if args.debug:
                print(f"DEBUG: FQDN keys: {sorted(list(vm_fqdns_output.keys()))}")
                print(f"DEBUG: IP keys: {sorted(list(vm_ipv4_addresses_output.keys()))}")
        
        for key, fqdn_string in vm_fqdns_output.items():
            ip_address = vm_ipv4_addresses_output.get(key)
            if fqdn_string and ip_address: # Ensure both FQDN and IP are not None or empty
                records_to_process.append({"domain": fqdn_string, "ip": ip_address})
                if args.debug:
                    print(f"DEBUG: Matched from dict: Key \'{key}\' -> FQDN \'{fqdn_string}\' with IP \'{ip_address}\'.")
            elif args.debug:
                print(f"DEBUG: Skipping record for key \'{key}\': FQDN=\'{fqdn_string}\', IP=\'{ip_address}\' (one or both are missing/empty).")

    elif isinstance(vm_fqdns_output, list) and isinstance(vm_ipv4_addresses_output, list):
        if args.debug:
            print(f"DEBUG: Processing FQDNs and IPs as lists. Matching based on order (index).")
        if len(vm_fqdns_output) != len(vm_ipv4_addresses_output):
            print(f"Warning: vm_fqdns_output (len {len(vm_fqdns_output)}) and vm_ipv4_addresses_output (len {len(vm_ipv4_addresses_output)}) have different lengths. Records might be mismatched or skipped.")

        for i, fqdn_string in enumerate(vm_fqdns_output):
            if i < len(vm_ipv4_addresses_output):
                ip_address = vm_ipv4_addresses_output[i]
                if fqdn_string and ip_address: # Ensure both FQDN and IP are not None or empty
                    records_to_process.append({"domain": fqdn_string, "ip": ip_address})
                    if args.debug:
                        print(f"DEBUG: Matched from list: Index {i} -> FQDN \'{fqdn_string}\' with IP \'{ip_address}\'.")
                elif args.debug:
                    print(f"DEBUG: Skipping record at index {i}: FQDN=\'{fqdn_string}\', IP=\'{ip_address}\' (one or both are missing/empty).")

            else:
                if args.debug:
                    print(f"DEBUG: No corresponding IP address found for FQDN \'{fqdn_string}\' at index {i} (IP list is shorter). Skipping.")
    else:
        print(f"ERROR: vm_fqdns_output (type: {type(vm_fqdns_output)}) and vm_ipv4_addresses_output (type: {type(vm_ipv4_addresses_output)}) are of incompatible or mixed types. Both must be lists or both must be dictionaries.")
        sys.exit(1)

    if not records_to_process:
        print("INFO: No matching DNS records found to process based on Terraform outputs after matching.")
        # sys.exit(0) # Allow script to finish normally even if no records
    else:
        if args.debug:
            print(f"DEBUG: Records to process ({args.action}): {records_to_process}")
            print("DEBUG: Debug mode enabled, showing records and exiting without processing:")
            for record in records_to_process:
                print(f"  - {record['domain']} -> {record['ip']}")
            sys.exit(0)
        else:
            print(f"INFO: Found {len(records_to_process)} DNS records to process with action '{args.action}'")

    for record in records_to_process:
        domain = record["domain"]
        ip_address = record["ip"]
        if args.action == "add":
            print(f"Attempting to add DNS record: {domain} -> {ip_address}")
            add_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=args.debug)
        elif args.action == "unregister-dns": # Changed from "delete"
            print(f"Attempting to unregister DNS record: {domain} (IP: {ip_address})")
            delete_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=args.debug)
    
    print(f"INFO: Script finished processing DNS records with action '{args.action}'.")

if __name__ == "__main__":
    main()
