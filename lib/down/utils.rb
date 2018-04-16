require "cgi"

module Down
  module Utils
    module_function

    def filename_from_content_disposition(content_disposition)
      content_disposition = content_disposition.to_s

      filename = content_disposition[/filename="([^"]*)"/, 1] || content_disposition[/filename=(.+)/, 1]
      filename = CGI.unescape(filename.to_s.strip)

      filename unless filename.empty?
    end

    def filename_from_path(path)
      filename = path.split("/").last
      CGI.unescape(filename) if filename
    end
  end
end
