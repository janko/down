# Down

Down is a wrapper around [open-uri] standard library for safe downloading of
remote files.

## Installation

```rb
gem 'down'
```

## Usage

```rb
require "down"
tempfile = Down.download("http://example.com/nature.jpg")
tempfile #=> #<Tempfile:/var/folders/k7/6zx6dx6x7ys3rv3srh0nyfj00000gn/T/20150925-55456-z7vxqz.jpg>
```

## Downloading

If you're downloading files from URLs that come from you, then it's probably
enough to just use `open-uri`. However, if you're accepting URLs from your
users (e.g. through `remote_<avatar>_url` in CarrierWave), then downloading is
suddenly not as simple as it appears to be.

### StringIO

Firstly, you may think that `open-uri` always downloads a file to disk, but
that's not true. If the downloaded file has 10 KB or less, `open-uri` actually
returns a `StringIO`. In my application I needed that the file is always
downloaded to disk. This was obviously a wrong design decision from the MRI
team, so Down patches this behaviour and always returns a `Tempfile`.

### File extension

When using `open-uri` directly, the extension of the remote file is not
preserved. Down patches that behaviour and preserves the file extension.

### Metadata

`open-uri` adds some metadata to the returned file, like `#content_type`. Down
adds `#original_filename` as well, which is extracted from the URL.

```rb
require "down"
tempfile = Down.download("http://example.com/nature.jpg")

tempfile #=> #<Tempfile:/var/folders/k7/6zx6dx6x7ys3rv3srh0nyfj00000gn/T/20150925-55456-z7vxqz.jpg>
tempfile.content_type #=> "image/jpeg"
tempfile.original_filename #=> "nature.jpg"
```

### Maximum size

When you're accepting URLs from an outside source, it's a good idea to limit
the filesize (because attackers want to give a lot of work to your servers).
Down allows you to pass a `:max_size` option:

```rb
Down.download("http://example.com/image.jpg", max_size: 5 * 1024 * 1024) # 5 MB
# raises Down::TooLarge
```

What is the advantage over simply checking size after downloading? Well, Down
terminates the download very early, as soon as it gets the `Content-Length`
header. And if the `Content-Length` header is missing, Down will terminate the
download as soon as it receives a chunk which surpasses the maximum size.

### Redirects

By default open-uri's redirects are turned off, since open-uri doesn't have a
way to limit maximum number of redirects. Instead Down itself implements
following redirects, by default allowing maximum of 2 redirects.

```rb
Down.download("http://example.com/image.jpg")                   # 2 redirects allowed
Down.download("http://example.com/image.jpg", max_redirects: 5) # 5 redirects allowed
Down.download("http://example.com/image.jpg", max_redirects: 0) # 0 redirects allowed
```

### Download errors

There are a lot of ways in which a download can fail:

* URL is really invalid (`URI::InvalidURIError`)
* URL is a little bit invalid, e.g. "http:/example.com" (`Errno::ECONNREFUSED`)
* Domain was not found (`SocketError`)
* Domain was found, but status is 4xx or 5xx (`OpenURI::HTTPError`)
* Request timeout (`Timeout::Error`)

Down unifies all of these errors into one `Down::NotFound` error (because this
is what actually happened from the outside perspective). If you want to get the
actual error raised by open-uri, in Ruby 2.1 or later you can use
`Exception#cause`:

```rb
begin
  Down.download("http://example.com")
rescue Down::Error => error
  error.cause #=> #<RuntimeError: HTTP redirection loop: http://example.com>
end
```

### Additional options

Any additional options will be forwarded to [open-uri], so you can for example
add basic authentication or a timeout:

```rb
Down.download "http://example.com/image.jpg",
  http_basic_authentication: ['john', 'secret'],
  read_timeout: 5
```

### Copying to tempfile

Down has another "hidden" utility method, `#copy_to_tempfile`, which creates
a Tempfile out of the given file. The `#download` method uses it internally,
but it's also publicly available for direct use:

```rb
io # IO object that you want to copy to tempfile
tempfile = Down.copy_to_tempfile "basename.jpg", io
tempfile.path #=> "/var/folders/k7/6zx6dx6x7ys3rv3srh0nyfj00000gn/T/down20151116-77262-jgcx65.jpg"
```

## Streaming

Down has the ability to access content of the remote file *as it is being
downloaded*. The `Down.open` method returns an IO object which represents the
remote file on the given URL. When you read from it, Down internally downloads
chunks of the remote file, but only how much is needed.

```rb
remote_file = Down.open("http://example.com/image.jpg")
remote_file.size # read from the "Content-Length" header

remote_file.read(1024) # downloads and returns first 1 KB
remote_file.read(1024) # downloads and returns next 1 KB
remote_file.read       # downloads and returns the rest of the file

remote_file.eof? #=> true
remote_file.rewind
remote_file.eof? #=> false

remote_file.close # closes the HTTP connection and deletes the internal Tempfile
```

You can also yield chunks directly as they're downloaded:

```rb
remote_file = Down.open("http://example.com/image.jpg")
remote_file.each_chunk do |chunk|
  # ...
end
remote_file.close
```

It accepts the `:ssl_verify_mode` and `:ssl_ca_cert` options with the same
semantics as in `open-uri`, and any options with String keys will be
interpreted as request headers.

```rb
Down.open("http://example.com/image.jpg", {"Authorization" => "..."})
```

### `Down::ChunkedIO`

The `Down.open` method uses `Down::ChunkedIO` internally. However,
`Down::ChunkedIO` is designed to be generic, it can wrap any kind of streaming.

```rb
Down::ChunkedIO.new(...)
```

* `:size` – size of the file, if it's known
* `:chunks` – an `Enumerator` which returns chunks
* `:on_close` – called when streaming finishes

Here is an example of wrapping streaming MongoDB files:

```rb
require "down/chunked_io"

mongo = Mongo::Client.new(...)
bucket = mongo.database.fs

content_length = bucket.find(_id: id).first["length"]
stream = bucket.open_download_stream(id)

io = Down::ChunkedIO.new(
  size: content_length,
  chunks: stream.enum_for(:each),
  on_close: -> { stream.close },
)
```

## Supported Ruby versions

* MRI 1.9.3
* MRI 2.0
* MRI 2.1
* MRI 2.2
* JRuby
* Rubinius

## Development

```
$ rake test
```

If you want to test across Ruby versions and you're using rbenv, run

```
$ bin/test-versions
```

## License

[MIT](LICENSE.txt)

[open-uri]: http://ruby-doc.org/stdlib-2.3.0/libdoc/open-uri/rdoc/OpenURI.html
