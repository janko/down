require "warning"

Gem.path.each do |path|
  Warning.ignore(//, path)
end

# Ruby emits this after a "method redefined" warning, but with the location of
# the original method, so we ignore it in favor of the "method redefined" one
Warning.ignore(/previous definition of \w+[?!]? was here/)

# Fail the test suite on any warnings except Down's own deprecation warnings
Warning.process do |warning|
  warning.start_with?("[Down::") ? :default : :raise
end
