# frozen_string_literal: true
# Union per tag of /cov/out/*/*.txt into /cov/<name>.txt: "# tag", "F path", "L path lines", "T sec" (max over owners).
name = ARGV.fetch(0)
tags = Hash.new { |h, k| h[k] = { files: {}, lines: Hash.new { |hh, kk| hh[kk] = {} }, t: nil, n: 0 } }
Dir["/cov/out/*/*.txt"].each do |fn|
  tag = nil
  File.foreach(fn) do |line|
    line.chomp!
    if line.start_with?("# ") then tag = line[2..]; tags[tag][:n] += 1
    elsif line.start_with?("F ") then tags[tag][:files][line[2..]] = true
    elsif line.start_with?("L ")
      _, p, ls = line.split(" ", 3)
      h = tags[tag][:lines][p]
      ls.split(",").each { |x| h[x.to_i] = true }
    elsif line.start_with?("T ")
      v = line[2..].to_f
      tags[tag][:t] = v if tags[tag][:t].nil? || v > tags[tag][:t]
    end
  end
end
out = +""
tags.each do |tag, d|
  out << "# #{tag}\nN #{d[:n]}\n"
  out << "T #{d[:t]}\n" if d[:t]
  d[:files].each_key { |p| out << "F #{p}\n" }
  d[:lines].each { |p, h| out << "L #{p} #{h.keys.sort.join(',')}\n" }
end
File.write("/cov/#{name}.txt", out)
puts "merged #{tags.size} tags from #{Dir['/cov/out/*/*.txt'].size} dumps -> /cov/#{name}.txt (#{out.bytesize} bytes)"
