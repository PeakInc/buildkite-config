#!/bin/bash
# Prints the coverage steps. PLAN=pilot: one small AR sqlite3 shard and one small railties dir. PLAN=railties: railties only. PLAN=full: everything.
q=hosted-4x16
step() { # label mode parallelism extra-env-yaml
  echo "  - label: \"$1\""
  echo "    command: bash testsel/harness/job.sh $2"
  echo "    agents: {queue: $q}"
  echo "    timeout_in_minutes: 50"
  [ "$3" -gt 1 ] && echo "    parallelism: $3"
  [ -n "${4:-}" ] && echo "    env: {$4}"
}
echo "steps:"
if [ "${PLAN:-full}" = pilot ]; then
  step "pilot ar-sqlite3" ar-sqlite3 1 "SHARD: '0', SHARDS: '40'"
  step "pilot railties commands" railties 1 "TEST_DIR: commands"
elif [ "${PLAN}" = railties ]; then
  step "railties coverage" railties 5
else
  step "railties coverage" railties 5
  step "ar sqlite3 coverage" ar-sqlite3 4
  step "ar postgresql coverage" ar-postgresql 4
fi
