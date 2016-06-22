require File.expand_path("../lib/down/version", __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "down"
  spec.version       = Down::VERSION
  spec.authors       = ["Janko Marohnić"]
  spec.email         = ["janko.marohnic@gmail.com"]

  spec.summary       = "Robust streaming downloads using net/http."
  spec.homepage      = "https://github.com/janko-m/down"
  spec.license       = "MIT"

  spec.files         = Dir["README.md", "LICENSE.txt", "*.gemspec", "lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest", "~> 5.8"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "mocha"
end
