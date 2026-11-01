#!/usr/bin/env bash
# Exits 0 when DRY_RUN, the dry-run input, is exactly true or false. Otherwise
# prints an error annotation and exits 1, because the merge steps treat every
# value other than true as permission to merge.
set -euo pipefail

case "${DRY_RUN-}" in
  true | false) ;;
  *)
    # The value is not echoed, since a newline in it would start a new
    # workflow command.
    echo "::error::The dry-run input must be true or false"
    exit 1
    ;;
esac
