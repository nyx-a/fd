#! /usr/bin/env ruby

require 'optparse'
require 'colorize'
require 'yaml'

SUBTREE_INDICATOR = ':'.freeze
INDENT            = 2

def comma n
  n.to_s.reverse.gsub(/\d{3}(?!$)/, '\&,').reverse
end

class FD
  attr_accessor :name
  attr_accessor :children
  attr_accessor :size

  @@show_total = false

  def self.show_total
    @@show_total
  end

  def self.show_total= bool
    @@show_total = bool
  end

  def self.from_hash(...)
    allocate.from_hash(...)
  end

  def self.load_file(...)
    allocate.load_file(...)
  end

  def self.scan_directory(...)
    allocate.scan_directory(...)
  end

  #-----

  def initialize something=nil
    case something
    when nil
    # make empty object
    when Hash
      from_hash something
    when String
      if File.directory? something
        self.scan_directory something # directory
      else
        self.load_file something # YAML file
      end
    else
      raise TypeError, "don't know how to handle #{something.class}"
    end
  end

  def from_hash hash
    @name     = hash[:name]
    @size     = hash[:size]
    @children = hash[:children]&.map{ FD.from_hash(**_1) }
    return self
  end

  def load_file filename
    data = YAML.load_file(filename)
    from_hash(**data)
  rescue TypeError
    STDERR.puts "it may not be a YAML file: #{filename}"
    raise
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
      fo.write YAML.dump to_hash
    end
    return filename
  end

  def scan_directory d
    @name = File.basename(d).unicode_normalize(:nfc)
    @children = [ ]
    for i in Dir.children d
      di = File.join d, i
      @children.push(File.directory?(di) ?
                       FD.scan_directory(di)
                     : FD.from_hash(
                         name: i.unicode_normalize(:nfc),
                         size: File.size(di)))
    end
    @children.sort!
    return self
  rescue Errno::ENOTDIR
    puts "Not a directory #{d}"
  end

  # このプログラムにとってファイルシステムのツリーはimmutableであり
  # あとから変更されることはない

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

  # children find
  # o is other FD object
  def cfind o
    candidate = @children.bsearch{ _1 >= o }
    if candidate&.name&.== o.name
      candidate
    end
  end

  # self.children - other.children を返す
  # other.name は見ない
  # ディレクトリではない要素を比較しようとすると
  # forかbsearchで例外出る筈だがこれはケアしない
  def csub other
    rest = [ ]
    for c in @children
      # 名前だけを頼りに候補を探す
      if o = other.cfind(c)
        if c.directory? and o.directory?
          diff = c.csub o
          if not diff.children.empty?
            rest.push diff
          end
        elsif c.directory? ^ o.directory?
          rest.push c
        else
          unless c.name == o.name and c.size == o.size
            rest.push c
          end
        end
      else
        rest.push c
      end
    end
    FD.new name: @name, children: rest
  end

  def == o
    @size==o.size and @name==o.name and @children==o.children
  end

  def <=> o
    x = (directory? ? -1 : 1) <=> (o.directory? ? -1 : 1)
    x.zero? ? @name <=> o.name : x
  end

  def >= o
    (self <=> o) >= 0
  end

  def <= o
    (self <=> o) <= 0
  end

  def subtree path
    breadcrumb = path.split File::SEPARATOR
    i = self
    until breadcrumb.empty?
      i = i.cfind FD.new(name: breadcrumb.shift, children: [ ])
      # childrenに空配列与えてるのはディレクトリ判定にするため
    end
    return i
  end

  def inspect indent: 0
    s = ' ' * indent
    if directory?
      if @name
        s += "#{@name.colorize :cyan}/\n"
      end
      for c in @children
        s += c.inspect(indent: indent+INDENT)
      end
      if @@show_total
        s += "#{' ' * (indent)}|       dirs: #{comma cd}\n".colorize :red
        s += "#{' ' * (indent)}|      files: #{comma cf}\n".colorize :red
        s += "#{' ' * (indent)}| total size: #{comma cs}\n".colorize :red
      end
    else
      s += "#{@name.colorize :yellow} #{comma(@size).colorize :blue}\n"
    end
    return s
  end
end

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

option = { }
o = OptionParser.new
o.on('-m',          '--monochrome', 'no colorize')
o.on('-s filename', '--serialize',  'serialize and save')
o.on('-i',          '--irb',        'irb')
o.on('-t',          '--total',      'toggle total count display')
o.parse! ARGV, into: option

if option[:monochrome]
  String.disable_colorization = true
end

if option[:total]
  FD.show_total = !FD.show_total
end

if option[:irb]
  binding.irb
  exit
end

if ARGV.empty?
  puts "usage:"
  puts "  #{$0} FD1 FD2 FD3 .. "
  puts
else
  array = [ ]
  flag = false
  for arg in ARGV
    if arg == SUBTREE_INDICATOR
      flag = true
    else
      if flag
        array.push array.pop.subtree arg
        flag = false
      else
        array.push FD.new arg
      end
    end
  end

  result = array.inject &:csub

  if option[:serialize]
    yamlfilename = result.save option[:serialize]
    puts "Saved: #{yamlfilename}"
    puts
  else
    p result
  end
end

