if RUBY_VERSION >= "2.4"
  require "warning"

  Gem.path.each do |path|
    Warning.ignore(//, path)
  end
end
