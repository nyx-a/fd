#! /usr/bin/env ruby

require 'yaml'

d = ARGV.empty? ? '.' : ARGV.shift

unless File.directory? d
  puts "usage:"
  puts "  #{$0} [Directory]"
  puts
  exit
end

def scan d
  container = Hash.new
  for i in Dir.children d
    path = File.join d, i
    if File.directory? path
      container[i] = scan path      # directory => { .. }
    else
      container[i] = File.size path # file => size
    end
  end
  container
end

puts YAML.dump scan d

