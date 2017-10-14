require File.expand_path("../lib/down/version", __FILE__)

Gem::Specification.new do |spec|
  spec.name         = "down"
  spec.version      = Down::VERSION

  spec.required_ruby_version = ">= 2.1"

  spec.summary      = "Robust streaming downloads using net/http."
  spec.homepage     = "https://github.com/janko-m/down"
  spec.authors      = ["Janko Marohnić"]
  spec.email        = ["janko.marohnic@gmail.com"]
  spec.license      = "MIT"

  spec.files        = Dir["README.md", "LICENSE.txt", "*.gemspec", "lib/**/*.rb"]
  spec.require_path = "lib"

  spec.add_development_dependency "minitest", "~> 5.8"
  spec.add_development_dependency "mocha"
  spec.add_development_dependency "http", "~> 3.0"
  spec.add_development_dependency "posix-spawn" unless RUBY_ENGINE == "jruby"
  spec.add_development_dependency "http_parser.rb"
  spec.add_development_dependency "docker-api"
end
