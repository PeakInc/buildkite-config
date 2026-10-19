# frozen_string_literal: true
# Loaded into every Ruby process via RUBYOPT=-r/cov/cov_harness.rb. Starts line coverage before Rails loads and,
# at exit (including exit! from forked test children), appends this process's coverage of /rails/**.rb to
# /cov/out/<tag>/<pid>-<n>.txt as plain text (no json: never load gems into test processes).
#   F <path>              file executed (any line)
#   L <path> <l1,l2,...>  executed lines, only for paths listed in /cov/interesting.txt
#   T <seconds>           wall seconds since this process took its tag (only the process that set the tag)
# The tag comes from ENV["COV_TAG"], inherited by forks and subprocesses. A process that loads a *_test.rb
# with COV_LOAD_TAG_PREFIX set takes the tag "<prefix><file>" and clears coverage first (railties' rake loop).
require "coverage"

module CovHarness
  ROOT = "/rails/"
  OUT = ENV["COV_OUT"] || "/cov/out"
  @dumped = false
  @t0 = nil
  @owner = nil

  class << self
    attr_accessor :t0, :owner

    def interesting
      @interesting ||= begin
        File.readlines(File.join(File.dirname(OUT), "interesting.txt"), chomp: true).to_h { |l| [l, true] }
      rescue StandardError
        {}
      end
    end

    def take_tag(tag)
      ENV["COV_TAG"] = tag
      Coverage.result(stop: false, clear: true) if Coverage.running?
      @t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @owner = Process.pid
      @dumped = false
    end

    def dump
      return unless Coverage.running?
      return if @dumped && @dumped_pid == Process.pid
      @dumped = true
      @dumped_pid = Process.pid
      res = Coverage.peek_result
      tag = (ENV["COV_TAG"] || "untagged").gsub(%r{[^A-Za-z0-9._-]}, "_")
      dir = File.join(OUT, tag)
      Dir.mkdir(OUT) unless Dir.exist?(OUT) rescue nil
      Dir.mkdir(dir) unless Dir.exist?(dir) rescue nil
      buf = +"# #{ENV['COV_TAG']}\n"
      int = interesting
      res.each do |path, cov|
        next unless path.start_with?(ROOT) && path.end_with?(".rb")
        lines = cov.is_a?(Hash) ? cov[:lines] : cov
        next unless lines
        hit = nil
        lines.each_with_index { |c, i| (hit ||= []) << (i + 1) if c && c > 0 }
        next unless hit
        rel = path.delete_prefix(ROOT)
        buf << "F #{rel}\n"
        buf << "L #{rel} #{hit.join(',')}\n" if int[rel]
      end
      if @t0 && @owner == Process.pid
        buf << "T #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0).round(3)}\n"
      end
      File.write(File.join(dir, "#{Process.pid}-#{rand(1 << 30)}.txt"), buf)
    rescue StandardError => e
      begin
        File.write(File.join(OUT, "errors-#{Process.pid}.txt"), "#{e.class}: #{e.message}\n")
      rescue StandardError
        nil
      end
    end
  end
end

unless Coverage.running?
  Coverage.start(lines: true)
end
at_exit { CovHarness.dump }

module CovHarnessExit
  def exit!(*args)
    CovHarness.dump
    super
  end
end
Kernel.prepend(CovHarnessExit)
Kernel.singleton_class.prepend(CovHarnessExit)
Process.singleton_class.prepend(CovHarnessExit)

if (prefix = ENV["COV_LOAD_TAG_PREFIX"])
  module CovHarnessLoad
    def load(file, *rest)
      if file.is_a?(String) && file.end_with?("_test.rb") && ENV["COV_TAG"].to_s.end_with?("__baseline__")
        CovHarness.take_tag("#{ENV['COV_LOAD_TAG_PREFIX']}#{file}")
      end
      super
    end
  end
  Kernel.prepend(CovHarnessLoad)
end
