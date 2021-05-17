if RUBY_VERSION >= "2.4"
  require "warning"

  Warning.process('', /instance variable @\w+ not initialized/ => :raise)
end
