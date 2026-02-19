require File.expand_path("../lib/down/version", __FILE__)

Gem::Specification.new do |spec|
  spec.name         = "down"
  spec.version      = Down::VERSION

  spec.required_ruby_version = ">= 2.7"

  spec.summary      = "Robust streaming downloads using Net::HTTP, http.rb or HTTPX."
  spec.homepage     = "https://github.com/janko/down"
  spec.authors      = ["Janko Marohnić"]
  spec.email        = ["janko.marohnic@gmail.com"]
  spec.license      = "MIT"

  spec.files        = Dir["README.md", "LICENSE.txt", "CHANGELOG.md", "*.gemspec", "lib/**/*.rb"]
  spec.require_path = "lib"

  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "base64", "~> 0.3"

  spec.add_development_dependency "minitest", "~> 5.8"
  spec.add_development_dependency "mocha", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "httpx", "~> 1.0"
  spec.add_development_dependency "http", "~> 5.0"
  spec.add_development_dependency "warning"
  spec.add_development_dependency "csv"
end
