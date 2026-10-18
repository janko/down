require "warning"

Gem.path.each do |path|
  Warning.ignore(//, path)
end

# Fail the test suite on any warnings coming from our code
root = File.expand_path("../..", __dir__)

Warning.process do |warning|
  warning.match?(%r{\A(#{Regexp.escape(root)}/)?(lib|test)/}) ? :raise : :default
end
