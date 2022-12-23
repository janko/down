if RUBY_VERSION >= "2.4"
  require "warning"

  Warning.process('', /instance variable @\w+ not initialized/ => :raise)

  Warning.ignore(/instance variable @\w+ not initialized/, Gem::Specification.find_by_name("httpx").load_paths.first)

  # ruby 2.5 or higher uses http.rb 5.0 which doesn't have http-parser as a dependency
  if RUBY_VERSION < "2.5"
    Warning.ignore(/interpreted as argument prefix/, Gem::Specification.find_by_name("http-parser").load_paths.first)
  end
end
