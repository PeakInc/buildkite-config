#!/bin/bash
# One coverage shard on a Buildkite hosted agent. MODE: railties | ar-sqlite3 | ar-postgresql.
set -uo pipefail
MODE=$1
IDX=${SHARD:-${BUILDKITE_PARALLEL_JOB:-0}}; N=${SHARDS:-${BUILDKITE_PARALLEL_JOB_COUNT:-1}}
export IMAGE_NAME=nscr.io/5j9uiopmtrqnk/rails-bench-builds:ruby-4-0-01a15052-776f-44d8-84b8-440bc0410bbe
mkdir -p cov/out ../test-reports
rm -f cov/current_tag
cp testsel/harness/cov_harness.rb testsel/harness/ar_runner.rb testsel/harness/merge.rb testsel/harness/interesting.txt cov/
chmod -R a+rwX cov ../test-reports
C="docker compose -f docker-compose.yml"
COMMON=(-v "$PWD/cov:/cov" -e RUBYOPT=-r/cov/cov_harness.rb -e BUILDKITE=true -e CI=true -e BUILDKITE_PARALLEL_JOB="$IDX" -e BUILDKITE_PARALLEL_JOB_COUNT="$N" ${TEST_DIR:+-e TEST_DIR="$TEST_DIR"})
start=$(date +%s)
case "$MODE" in
  railties)
    echo "--- :docker: pull"; $C pull -q railties --include-deps
    echo "+++ railties coverage shard $IDX/$N"
    $C run --rm "${COMMON[@]}" -e COV_TAG=railties/__baseline__ -e COV_LOAD_TAG_PREFIX=railties/ railties runner railties 'rake test' ;;
  ar-sqlite3)
    echo "--- :docker: pull"; $C pull -q default
    echo "+++ activerecord sqlite3 coverage shard $IDX/$N"
    $C run --rm "${COMMON[@]}" -e ARCONN=sqlite3 -e COV_TAG=ar-sqlite3/__baseline__ default runner activerecord "ruby -w -Itest -Ilib /cov/ar_runner.rb $IDX $N" ;;
  ar-postgresql)
    echo "--- :docker: pull"; $C pull -q postgresdb --include-deps
    echo "+++ activerecord postgresql coverage shard $IDX/$N"
    $C run --rm "${COMMON[@]}" -e ARCONN=postgresql -e COV_TAG=ar-postgresql/__baseline__ postgresdb runner activerecord "bundle exec rake db:postgresql:rebuild && ruby -w -Itest -Ilib /cov/ar_runner.rb $IDX $N" ;;
esac
rc=$?
echo "--- elapsed $(( $(date +%s) - start ))s rc=$rc; merging"
$C run --rm -v "$PWD/cov:/cov" -e RUBYOPT= default ruby /cov/merge.rb "merged-$MODE-$IDX" || true
gzip -f cov/merged-*.txt 2>/dev/null || true
ls -la cov | head -20; du -sh cov/out 2>/dev/null
cat cov/out/errors-*.txt 2>/dev/null | sort | uniq -c | head -5
buildkite-agent artifact upload "cov/merged-*.txt.gz" || true
buildkite-agent artifact upload "cov/times-*.txt" || true
$C down -v >/dev/null 2>&1 || true
exit 0
