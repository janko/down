Gem::Specification.new do |spec|
  spec.name          = "down"
  spec.version       = "2.2.1"
  spec.authors       = ["Janko Marohnić"]
  spec.email         = ["janko.marohnic@gmail.com"]

  spec.summary       = "Robust streaming downloads using net/http."
  spec.homepage      = "https://github.com/janko-m/down"
  spec.license       = "MIT"

  spec.files         = ["README.md", "LICENSE.txt", "down.gemspec", "lib/down.rb"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest", "~> 5.8"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "mocha"
end
