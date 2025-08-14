#!/usr/bin/env python

import json
import os
import argparse

def get_inventory_data():
    # Try to read from cache file first
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    cache_file = os.path.join(repo_root, '.ansible_inventory_cache.json')
    
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    
    # Return empty inventory if no cache
    return {
        "_meta": {"hostvars": {}},
        "all": {"children": ["ungrouped"]},
        "ungrouped": {"hosts": ["localhost"]},
        "_meta": {"hostvars": {"localhost": {"ansible_connection": "local"}}}
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--host', action='store')
    args = parser.parse_args()

    inventory = get_inventory_data()

    if args.list:
        print(json.dumps(inventory, indent=4))
    elif args.host:
        # Not strictly necessary for basic use, but good practice
        print(json.dumps(inventory.get("_meta", {}).get("hostvars", {}).get(args.host, {}), indent=4))
    else:
        print(json.dumps(inventory, indent=4))

if __name__ == "__main__":
    main()
