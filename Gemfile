source "https://rubygems.org"

gemspec

gem "pry"
gem "memory_profiler"
gem "puma"
gem "rack"

# Type checking (Steep and RBS require Ruby 3.3+)
if RUBY_ENGINE == "ruby" && RUBY_VERSION >= "3.3"
  gem "steep", "~> 2.1"
  gem "rbs", "~> 4.2"
  gem "rbs-inline", "~> 0.14"
end
