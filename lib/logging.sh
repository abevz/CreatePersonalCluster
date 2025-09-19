#!/bin/bash
# =============================================================================
# CPC Logging Library
# =============================================================================
# Provides standardized logging functions for the CPC project

# --- Logging Functions ---

log_info() {
  echo -e "${BLUE}$*${ENDCOLOR}"
}

log_success() {
  echo -e "${GREEN}$*${ENDCOLOR}"
}

log_warning() {
  echo -e "${YELLOW}$*${ENDCOLOR}" >&2
}

log_error() {
  echo -e "${RED}$*${ENDCOLOR}" >&2
}

log_debug() {
  if [ "${CPC_DEBUG:-}" = "true" ]; then
    echo -e "${PURPLE}[DEBUG] $*${ENDCOLOR}"
  fi
}

log_header() {
  echo -e "${CYAN}=== $* ===${ENDCOLOR}"
}

log_step() {
  echo -e "${WHITE}➤ $*${ENDCOLOR}"
}

# Progress indicator for long operations
log_progress() {
  local message="$1"
  local current="$2"
  local total="$3"

  local percentage=$((current * 100 / total))
  echo -e "${BLUE}[$current/$total] ($percentage%) $message${ENDCOLOR}"
}

# Log command execution with highlighting
log_command() {
  echo -e "${PURPLE}Running: ${WHITE}$*${ENDCOLOR}"
}

# Multi-line output formatting
log_block() {
  echo -e "${BLUE}────────────────────────────────────────${ENDCOLOR}"
  while IFS= read -r line; do
    echo -e "${BLUE}│${ENDCOLOR} $line"
  done
  echo -e "${BLUE}────────────────────────────────────────${ENDCOLOR}"
}

# Conditional logging based on verbosity level
log_verbose() {
  if [ "${CPC_VERBOSE:-}" = "true" ]; then
    log_info "$@"
  fi
}

# Error handling with stack trace
log_fatal() {
  log_error "FATAL: $*"
  if [ "${CPC_DEBUG:-}" = "true" ]; then
    log_error "Stack trace:"
    local i=0
    while caller $i; do
      ((i++))
    done
  fi
  exit 1
}

# Validation result logging
log_validation() {
  local status="$1"
  local message="$2"

  case "$status" in
  "pass" | "ok" | "success")
    echo -e "${GREEN}✓${ENDCOLOR} $message"
    ;;
  "fail" | "error" | "failed")
    echo -e "${RED}✗${ENDCOLOR} $message"
    ;;
  "skip" | "skipped")
    echo -e "${YELLOW}⚬${ENDCOLOR} $message"
    ;;
  *)
    echo -e "${BLUE}•${ENDCOLOR} $message"
    ;;
  esac
}

# Export logging functions
export -f log_info log_success log_warning log_error log_debug
export -f log_header log_step log_progress log_command log_block
export -f log_verbose log_fatal log_validation
