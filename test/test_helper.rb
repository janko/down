require "bundler/setup"

ENV["MT_NO_EXPECTATIONS"] = "1"

require "minitest"
require "minitest/spec"
require "minitest/pride"

# Mocha still references the old constant
MiniTest = Minitest unless defined?(MiniTest)
require "mocha/minitest"

require_relative "support/deprecated_helper"
require_relative "support/warnings"

require "http"

$httpbin = "http://localhost"

begin
  HTTP.get($httpbin).to_s
rescue HTTP::ConnectionError
  warn <<-WARNING

The httpbin server is not running on port 80, which is required for tests. Please run:

$ docker pull kennethreitz/httpbin
$ docker run -p 80:80 kennethreitz/httpbin

WARNING
  exit 1
end

Minitest.autorun
