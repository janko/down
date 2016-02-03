Gem::Specification.new do |spec|
  spec.name          = "down"
  spec.version       = "2.0.0"
  spec.authors       = ["Janko Marohnić"]
  spec.email         = ["janko.marohnic@gmail.com"]

  spec.summary       = "Robust file download from URL using open-uri."
  spec.description   = "Robust file download from URL using open-uri."
  spec.homepage      = "https://github.com/janko-m/down"
  spec.license       = "MIT"

  spec.files         = ["README.md", "LICENSE.txt", "down.gemspec", "lib/down.rb"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest", "~> 5.8"
  spec.add_development_dependency "webmock"
end
