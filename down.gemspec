require File.expand_path("../lib/down/version", __FILE__)

Gem::Specification.new do |spec|
  spec.name         = "down"
  spec.version      = Down::VERSION

  spec.required_ruby_version = ">= 3.2"

  spec.summary      = "Robust streaming downloads using Net::HTTP, http.rb or HTTPX."
  spec.homepage     = "https://github.com/janko/down"
  spec.authors      = ["Janko Marohnić"]
  spec.email        = ["janko.marohnic@gmail.com"]
  spec.license      = "MIT"

  spec.files        = Dir["README.md", "LICENSE.txt", "CHANGELOG.md", "*.gemspec", "lib/**/*.rb", "sig/**/*.rbs", "sig/manifest.yaml"]
  spec.require_path = "lib"

  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "base64", "~> 0.3"
  spec.add_dependency "tempfile", ">= 0.3.1" # Tempfile.create(anonymous: true)

  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "mocha", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "httpx", "~> 1.0", "< 1.4.4"
  spec.add_development_dependency "http", "~> 6.0"
  spec.add_development_dependency "warning"
  spec.add_development_dependency "csv"
end
