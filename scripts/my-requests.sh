#!/bin/bash
# List the user's own submit requests (roles=creator), grouped by state — thin
# wrapper over `sr-status.py --brief --no-prs` (single implementation of the
# discovery query). `osc rq list -U` is NOT a creator filter (it returns
# anything you're involved in, incl. as reviewer), so this uses the
# request-search API with roles=creator (via sr-status.py).
#
# Usage: my-requests.sh [--state open|declined|accepted|all] [--user OBSUSER] [--target PRJ]
#   --state   open (new,review) | declined | accepted | all   (default: open)
#   --user    OBS account (default: `osc whois`)
#   --target  restrict to a target project (e.g. openSUSE:Factory)
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0"; exit 0;;
esac

exec "$(dirname "$0")/sr-status.py" --brief --no-prs "$@"
