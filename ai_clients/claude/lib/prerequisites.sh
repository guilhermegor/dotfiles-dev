#!/bin/bash
# Validates that required tools are present before running any setup step.

check_prerequisites() {
    print_status "section" "CHECKING PREREQUISITES"

    if ! command -v jq &>/dev/null; then
        print_status "error" "jq is required but not installed"
        print_status "info" "Install: sudo apt install jq"
        exit 1
    fi
    print_status "success" "jq found"

    if ! command -v claude &>/dev/null; then
        print_status "error" "claude CLI not found in PATH"
        exit 1
    fi
    print_status "success" "claude CLI found"
}
