# frozen_string_literal: true
# Runs each Active Record test file in its own fork of one booted process (helper + schema loaded once), so
# each file's coverage (load time and run time) is its own. Usage, in activerecord/:
#   COV_TAG=ar-<adapter>/__baseline__ ARCONN=<adapter> ruby -w -Itest -Ilib /cov/ar_runner.rb <shard> <shards>
adapter = ENV.fetch("ARCONN")
shard, shards = ARGV.map(&:to_i)
ARGV.clear
short = adapter[/^[a-z0-9]+/]
files = (Dir["test/cases/**/*_test.rb"].reject { |x| x.include?("/adapters/") } + Dir["test/cases/adapters/#{short}/**/*_test.rb"]).sort
mine = files.each_with_index.select { |_, i| i % shards == shard }.map(&:first)
$stdout.sync = true
puts "ar_runner: #{adapter} shard #{shard}/#{shards}: #{mine.size} of #{files.size} files"
require "cases/helper"
times = []
mine.each do |f|
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = fork do
    CovHarness.take_tag("ar-#{adapter}/#{f}")
    load f
  end
  Process.wait(pid)
  dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  times << [f, dt.round(3), $?.exitstatus]
  puts "--- #{f} #{dt.round(1)}s status=#{$?.exitstatus}"
end
File.write("/cov/times-ar-#{adapter}-#{shard}.txt", times.map { |a| a.join("\t") }.join("\n") + "\n")
CovHarness.dump
exit!(0)
