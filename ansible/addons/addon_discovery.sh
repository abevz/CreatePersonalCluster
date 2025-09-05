#!/bin/bash
# =============================================================================
# Addon Discovery System for CPC
# =============================================================================

# Discover all available addons dynamically
addon_discover_all() {
  local addon_dir="${1:-$(pwd)/ansible/addons}"
  
  # Ensure addon directory exists
  if [[ ! -d "$addon_dir" ]]; then
    return 1
  fi
  
  declare -gA DISCOVERED_ADDONS
  declare -gA ADDON_CATEGORIES
  
  # Find all addon YAML files
  while IFS= read -r -d '' addon_file; do
    local addon_name="$(basename "$addon_file" .yml)"
    local addon_category="$(basename "$(dirname "$addon_file")")"
    
    # Skip if not a valid addon file
    [[ "$addon_name" == "addon_"* ]] && continue
    
    DISCOVERED_ADDONS["$addon_name"]="$addon_file"
    ADDON_CATEGORIES["$addon_name"]="$addon_category"
    
  done < <(find "$addon_dir" -name "*.yml" -type f -print0 2>/dev/null)
  
  return 0
}

# Get list of addons by category
addon_list_by_category() {
  local category="$1"
  local -a addons_in_category=()
  
  for addon in "${!ADDON_CATEGORIES[@]}"; do
    if [[ "${ADDON_CATEGORIES[$addon]}" == "$category" ]]; then
      addons_in_category+=("$addon")
    fi
  done
  
  printf '%s\n' "${addons_in_category[@]}" | sort
}

# Get all available categories
addon_get_categories() {
  local -a categories=()
  
  for category in "${ADDON_CATEGORIES[@]}"; do
    if [[ ! " ${categories[*]} " =~ " ${category} " ]]; then
      categories+=("$category")
    fi
  done
  
  printf '%s\n' "${categories[@]}" | sort
}

# Display interactive addon menu with categories
addon_display_interactive_menu() {
  local -i choice_num=1
  local -a choice_to_addon
  
  echo -e "${BLUE}Select addon to install/upgrade:${ENDCOLOR}" >&2
  echo "" >&2
  echo "  ${choice_num}) all                          - Install/upgrade all addons" >&2
  choice_to_addon[$choice_num]="all"
  ((choice_num++))
  echo "" >&2
  
  # Show discovered addons by category in proper order
  local -a categories
  readarray -t categories < <(addon_get_categories)
  
  for category in "${categories[@]}"; do
    echo -e "${YELLOW}━━━ $(echo "$category" | tr '[:lower:]' '[:upper:]') ━━━${ENDCOLOR}" >&2
    
    local -a addons_in_cat
    readarray -t addons_in_cat < <(addon_list_by_category "$category")
    
    for addon in "${addons_in_cat[@]}"; do
      local description
      description=$(addon_get_description "$addon")
      printf "  %2d) %-30s - %s\n" $choice_num "$addon" "$description" >&2
      choice_to_addon[$choice_num]="$addon"
      ((choice_num++))
    done
  done
  
  echo "" >&2
  read -r -p "Enter your choice [1-$((choice_num-1))]: " choice
  
  if [[ "$choice" -ge 1 && "$choice" -le $((choice_num-1)) && -n "${choice_to_addon[$choice]}" ]]; then
    echo "${choice_to_addon[$choice]}"
    return 0
  else
    echo "Invalid choice: $choice" >&2
    return 1
  fi
}

# Get addon description from metadata
addon_get_description() {
  local addon_name="$1"
  local addon_file="${DISCOVERED_ADDONS[$addon_name]}"
  
  if [[ -f "$addon_file" ]]; then
    # Try to extract description from YAML comment
    local description
    description=$(grep -m1 "^# Description:" "$addon_file" 2>/dev/null | sed 's/^# Description: *//')
    
    if [[ -n "$description" ]]; then
      echo "$description"
    else
      echo "No description available"
    fi
  else
    echo "Unknown addon"
  fi
}

# Validate addon exists
addon_validate_exists() {
  local addon_name="$1"
  
  if [[ "$addon_name" == "all" ]]; then
    return 0
  fi
  
  if [[ -n "${DISCOVERED_ADDONS[$addon_name]}" ]]; then
    return 0
  else
    log_error "Addon '$addon_name' not found."
    log_info "Available addons: $(printf '%s ' "${!DISCOVERED_ADDONS[@]}" | sort)"
    return 1
  fi
}

# Get addon file path
addon_get_path() {
  local addon_name="$1"
  echo "${DISCOVERED_ADDONS[$addon_name]}"
}

# Get addon category
addon_get_category() {
  local addon_name="$1"
  echo "${ADDON_CATEGORIES[$addon_name]}"
}

# List all available addons
addon_list_all() {
  local format="${1:-simple}"
  
  case "$format" in
    "simple")
      for addon in "${!DISCOVERED_ADDONS[@]}"; do
        echo "$addon"
      done | sort
      ;;
    "detailed")
      echo -e "${BLUE}Available Addons:${ENDCOLOR}"
      echo ""
      local -a categories
      readarray -t categories < <(addon_get_categories)
      
      for category in "${categories[@]}"; do
        echo -e "${YELLOW}$(echo "$category" | tr '[:lower:]' '[:upper:]'):${ENDCOLOR}"
        local -a addons_in_cat
        readarray -t addons_in_cat < <(addon_list_by_category "$category")
        
        for addon in "${addons_in_cat[@]}"; do
          local description
          description=$(addon_get_description "$addon")
          printf "  %-20s - %s\n" "$addon" "$description"
        done
        echo ""
      done
      ;;
  esac
}

# Initialize addon discovery system
addon_discovery_init() {
  local addon_dir="${REPO_PATH:-$(pwd)}/addons"
  addon_discover_all "$addon_dir"
  if [[ ${#DISCOVERED_ADDONS[@]} -gt 0 ]]; then
    log_debug "Discovered ${#DISCOVERED_ADDONS[@]} addons across $(addon_get_categories | wc -l) categories"
  else
    log_debug "No addon modules found in $addon_dir"
  fi
}
