source "https://rubygems.org"

gemspec

gem "pry"
gem "memory_profiler"

if RUBY_VERSION == "2.7.0"
  gem "http",           github: "janko/http",      branch: "ruby-2-7-compatibility"
  gem "http-form_data", github: "janko/form_data", branch: "ruby-2-7-compatibility"
end
