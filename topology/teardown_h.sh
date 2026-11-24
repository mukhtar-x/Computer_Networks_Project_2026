#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

printf '==== Teardown namespaces ====\n'
for ns in h1 h2 h3 h4 h5 h6 sw1 sw2 r1 r2 s1; do
    if ip netns list 2>/dev/null | awk '{print $1}' | grep -Fxq "$ns"; then
        ip netns del "$ns" >/dev/null 2>&1
    fi
done
printf 'Removed project namespaces and their veth links.\n'
