require "warning"

Warning.process('', /instance variable @\w+ not initialized/ => :raise)
Warning.ignore(/interpreted as argument prefix/, Gem::Specification.find_by_name("http-parser").load_paths.first)
