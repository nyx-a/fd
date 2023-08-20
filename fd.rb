#! /usr/bin/env ruby

require 'optparse'
require 'colorize'
require 'yaml'
require_relative 'b.structure.rb'

def comma n
  n.to_s.reverse.gsub(/\d{3}(?!$)/, '\&,').reverse
end

class FD < B::Structure
  attr_accessor :name
  attr_accessor :children
  attr_accessor :size

  def self.load filename
    self.new(**YAML.load_file(filename))
  end

  def initialize **hash
    @name     = hash[:name]
    @size     = hash[:size]
    @children = hash[:children]&.map{ self.class.new(**_1) }
  end

  # このノード以下の(自身を含む)ファイルの合計
  def cf
    @cf ||= @children&.sum(&:cf) || 1
  end

  # このノード以下の(自身を含む)ファイルサイズの合計
  def cs
    @cs ||= @children&.sum(&:cs) || @size
  end

  # このノード以下の(自身を含む)ディレクトリの合計
  def cd
    @cd ||= (@children&.sum(&:cd) &.+ 1) || 0
  end

  def directory?
    not @children.nil?
  end

  def scan d
    @name = File.basename(d).unicode_normalize(:nfc)
    @children = [ ]
    for i in Dir.children d
      di = File.join d, i
      @children.push(File.directory?(di) ?
                       FD.new.scan(di)
                     : FD.new(name: i.unicode_normalize(:nfc), size: File.size(di)))
    end
    @children.sort!
    return self
  rescue Errno::ENOTDIR
    puts "Not a directory #{d}"
  end

  def csub other
    unless self.directory? and other.directory?
      raise TypeError
    end
    left = [ ]
    for i in @children
      if i.directory?
        o = other.children.find{ _1.directory? and _1.name==i.name }
        if o.nil?
          left.push i
        else
          sb = i.csub o
          unless sb.empty?
            left.push FD.new(name: i.name, children: sb)
          end
        end
      else
        unless other.children.include? i
          left.push i
        end
      end
    end
    left
  end

  def == o
    @size==o.size and @name==o.name and @children==o.children
  end

  def eql? o
    @size.eql?(o.size) and @name.eql?(o.name) and @children.eql?(o.children)
  end

  def <=> o
    x = (directory? ? 1 : -1) <=> (o.directory? ? 1 : -1)
    x.zero? ? @name <=> o.name : x
  end

  def to_hash
    {
      name: @name,
      size: @size,
      children: @children&.map(&:to_hash),
    }
  end

  def save filename
    filename = filename.sub(/\.ya?ml$/i, '') + '.yaml'
    open(filename, 'w') do |fo|
      fo.write YAML.dump self.to_hash
    end
  end

  def from_hash h
    @name = h[:name]
    @size = h[:size]
    @children = h[:children].map
  end

  def inspect indent: 0
    s = ' ' * indent
    if directory?
      s += "#{@name.colorize :yellow}/\n"
      for c in @children
        s += c.inspect(indent: indent+2)
      end
      s += "#{' ' * (indent)}|       dirs: #{comma cd}\n".colorize :red
      s += "#{' ' * (indent)}|      files: #{comma cf}\n".colorize :red
      s += "#{' ' * (indent)}| total size: #{comma cs}\n".colorize :red
    else
      s += "#{@name.colorize :cyan} #{comma(@size).colorize :blue}\n"
    end
    return s
  end
end

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

option = { }
o = OptionParser.new
o.on('-m', '--monochrome', 'no colorize')
o.on('-s filename', '--serialize', 'serialize and save')
o.on('-d filename(s)', '--deserialize', Array, 'load file(s)')
o.parse! ARGV, into: option

if option[:monochrome]
  String.disable_colorization = true
end

case ARGV.size
when 0
  if option[:deserialize]
    option[:deserialize][0]
    option[:deserialize][1]
  end
when 1
  if File.directory? ARGV.first
    o = FD.new.scan ARGV.first
    if option[:serialize]
      o.save option[:serialize]
    else
      p o
    end
  else
    p FD.load ARGV.first
  end
when 2
  a = FD.new.scan ARGV[0]
  b = FD.new.scan ARGV[1]
  puts a.csub(b).map(&:inspect)
  puts
else
  puts "usage:"
  puts "  #{$0} [file1] [(file2)]"
  puts
  exit
end

