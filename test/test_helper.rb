require "bundler/setup"

ENV["MT_NO_EXPECTATIONS"] = "1"

require "minitest"
require "minitest/spec"
require "minitest/pride"

require "http"

if ENV["CI"]
  $httpbin = "http://httpbin.org"
else
  output_rd, output_wr = IO.pipe

  begin
    pid = spawn "gunicorn httpbin:app", [:out, :err] => output_wr
  rescue Errno::ENOENT
    abort "ERROR: \"gunicorn\" Python package is not installed"
  end

  output = []
  output << output_rd.gets
  output << output_rd.gets

  $httpbin = output.last[/Listening at: (\S+)/, 1]

  begin
    HTTP.timeout(read: 1).get("#{$httpbin}/")
  rescue HTTP::TimeoutError
    output << output_rd.readpartial(16*1024)
    output = output.join("\n")

    if output.include?("ImportError: No module named httpbin")
      abort "ERROR: \"httpbin\" Python package is not installed"
    else
      abort "ERROR: Unable to start the httpin app:\n#{output}"
    end
  end

  Thread.new { output_rd.read } # continue reading output

  at_exit { Process.kill("TERM", pid) }
end

Minitest.autorun
