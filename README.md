# Down

Down is a utility tool for streaming, flexible and safe downloading of remote
files. It can use [open-uri] + `Net::HTTP` or [HTTP.rb] as the backend HTTP
library.

## Installation

```rb
gem "down"
```

## Downloading

The primary method is `Down.download`, which downloads the remote file into a
Tempfile:

```rb
require "down"
tempfile = Down.download("http://example.com/nature.jpg")
tempfile #=> #<Tempfile:/var/folders/k7/6zx6dx6x7ys3rv3srh0nyfj00000gn/T/20150925-55456-z7vxqz.jpg>
```

### Metadata

The returned Tempfile has `#content_type` and `#original_filename` attributes
determined from the response headers:

```rb
tempfile.content_type      #=> "image/jpeg"
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
download as soon as the downloaded content surpasses the maximum size.

### Basic authentication

`Down.download` and `Down.open` will automatically detect and apply HTTP basic
authentication from the URL:

```rb
Down.download("http://user:password@example.org")
Down.open("http://user:password@example.org")
```

### Download errors

There are a lot of ways in which a download can fail:

* Response status was 4xx or 5xx
* Domain was not found
* Timeout occurred
* URL is invalid
* ...

Down attempts to unify all of these exceptions into one `Down::NotFound` error
(because this is what actually happened from the outside perspective). If you
want to retrieve the original error raised, in Ruby 2.1+ you can use
`Exception#cause`:

```rb
begin
  Down.download("http://example.com")
rescue Down::Error => exception
  exception.cause #=> #<Timeout::Error>
end
```

## Streaming

Down has the ability to retrieve content of the remote file *as it is being
downloaded*. The `Down.open` method returns a `Down::ChunkedIO` object which
represents the remote file on the given URL. When you read from it, Down
internally downloads chunks of the remote file, but only how much is needed.

```rb
remote_file = Down.open("http://example.com/image.jpg")
remote_file.size # read from the "Content-Length" header

remote_file.read(1024) # downloads and returns first 1 KB
remote_file.read(1024) # downloads and returns next 1 KB

remote_file.eof? #=> false
remote_file.read # downloads and returns the rest of the file content
remote_file.eof? #=> true

remote_file.close # closes the HTTP connection and deletes the internal Tempfile
```

### Caching

By default the downloaded content is internally cached into a `Tempfile`, so
that when you rewind the `Down::ChunkedIO`, it continues reading the cached
content that it had already retrieved.

```rb
remote_file = Down.open("http://example.com/image.jpg")
remote_file.read(1*1024*1024) # downloads, caches, and returns first 1MB
remote_file.rewind
remote_file.read(1*1024*1024) # reads the cached content
remote_file.read(1*1024*1024) # downloads the next 1MB
```

If you want to save on IO calls and on disk usage, and don't need to be able to
rewind the `Down::ChunkedIO`, you can disable caching downloaded content:

```rb
Down.open("http://example.com/image.jpg", rewindable: false)
```

### Yielding chunks

You can also yield chunks directly as they're downloaded via `#each_chunk`, in
which case the downloaded content is not cached into a file regardless of the
`:rewindable` option.

```rb
remote_file = Down.open("http://example.com/image.jpg")
remote_file.each_chunk { |chunk| ... }
remote_file.close
```

### Data

You can access the response status and headers of the HTTP request that was made:

```rb
remote_file = Down.open("http://example.com/image.jpg")
remote_file.data[:status]   #=> 200
remote_file.data[:headers]  #=> { ... }
remote_file.data[:response] # returns the response object
```

Note that `Down::NotFound` error will automatically be raised if response
status was 4xx or 5xx.

### `Down::ChunkedIO`

The `Down.open` method uses `Down::ChunkedIO` internally. However,
`Down::ChunkedIO` is designed to be generic, it can wrap any kind of streaming.

```rb
Down::ChunkedIO.new(...)
```

* `:chunks` – an `Enumerator` which retrieves chunks
* `:size` – size of the file if it's known (returned by `#size`)
* `:on_close` – called when streaming finishes or IO is closed
* `:data` - custom data that you want to store (returned by `#data`)
* `:rewindable` - whether to cache retrieved data into a file (defaults to `true`)
* `:encoding` - force content to be returned in specified encoding (defaults to `Encoding::BINARY`)

Here is an example of wrapping streaming MongoDB files:

```rb
require "down/chunked_io"

mongo = Mongo::Client.new(...)
bucket = mongo.database.fs

content_length = bucket.find(_id: id).first[:length]
stream = bucket.open_download_stream(id)

io = Down::ChunkedIO.new(
  size: content_length,
  chunks: stream.enum_for(:each),
  on_close: -> { stream.close },
)
```

## open-uri + Net::HTTP

Then [open-uri] + Net::HTTP is the default backend, loaded by requiring `down`
or `down/net_http`:

```rb
require "down"
# or
require "down/net_http"
```

`Down.download` is implemented as a wrapper around open-uri, and fixes some of
open-uri's undesired behaviours:

* open-uri returns `StringIO` for files smaller than 10KB, and `Tempfile`
  otherwise, but `Down.download` always returns a `Tempfile`
* open-uri doesn't give any extension to the returned `Tempfile`, but
  `Down.download` adds the extension from the URL
* ...

Since open-uri doesn't expose support for partial downloads, `Down.open` is
implemented using `Net::HTTP` directly.

### Redirects

`Down.download` turns off open-uri's following redirects, as open-uri doesn't
have a way to limit the maximum number of hops, and implements its own. By
default maximum of 2 redirects will be followed, but you can change it via the
`:max_redirects` option:

```rb
Down.download("http://example.com/image.jpg")                   # 2 redirects allowed
Down.download("http://example.com/image.jpg", max_redirects: 5) # 5 redirects allowed
Down.download("http://example.com/image.jpg", max_redirects: 0) # 0 redirects allowed
```

### Proxy

Both `Down.download` and `Down.open` support a `:proxy` option, where you can
specify a URL to an HTTP proxy which should be used when downloading.

```rb
Down.download("http://example.com/image.jpg", proxy: "http://proxy.org")
Down.open("http://example.com/image.jpg",     proxy: "http://user:password@proxy.org")
```

### Additional options

Any additional options passed to `Down.download` will be forwarded to
[open-uri], so you can for example add basic authentication or a timeout:

```rb
Down.download "http://example.com/image.jpg",
  http_basic_authentication: ['john', 'secret'],
  read_timeout: 5
```

`Down.open` accepts `:ssl_verify_mode` and `:ssl_ca_cert` options with the same
semantics as in open-uri, and any options with String keys will be interpreted
as request headers, like with open-uri.

```rb
Down.open("http://example.com/image.jpg", {"Authorization" => "..."})
```

## HTTP.rb

The [HTTP.rb] backend can be used by requiring `down/http`:

```rb
gem "http", "~> 2.1"
gem "down"
```
```rb
require "down/http"
tempfile = Down.download("http://example.org/image.jpg")
tempfile #=> #<Tempfile:/var/folders/k7/6zx6dx6x7ys3rv3srh0nyfj00000gn/T/20150925-55456-z7vxqz.jpg>
```

Some features that give the HTTP.rb backend an advantage over open-uri +
Net::HTTP include:

* Correct URI parsing with [Addressable::URI]
* Proper support for streaming downloads (`#download` and now reuse `#open`)
* Proper support for SSL
* Chaninable HTTP client builder API for setting default options
* Persistent connections
* Auto-inflating compressed response bodies
* ...

### Default client

You can change the default `HTTP::Client` to be used in all download requests
via `Down::Http.client`:

```rb
# reuse Down's default client
Down::Http.client = Down::Http.client.timeout(read: 3).feature(:auto_inflate)
Down::Http.client.default_options.merge!(ssl_context: ctx)

# or set a new client
Down::Http.client = HTTP.via("proxy-hostname.local", 8080)
```

### Additional options

All additional options passed to `Down::Download` and `Down.open` will be
forwarded to `HTTP::Client#request`:

```rb
Down.download("http://example.org/image.jpg", headers: {"Accept-Encoding" => "gzip"})
```

If you prefer to add options using the chainable API, you can pass a block:

```rb
Down.open("http://example.org/image.jpg") do |client|
  client.timeout(read: 3)
end
```

### Thread safety

`Down::Http.client` is stored in a thread-local variable, so using the HTTP.rb
backend is thread safe.

## Supported Ruby versions

* MRI 2.2
* MRI 2.3
* MRI 2.4
* JRuby

## Development

The test suite runs the http://httpbin.org/ server locally, and uses it to test
downloads. Httpbin is a Python package which is run with GUnicorn:

```
$ pip install gunicorn httpbin
```

Afterwards you can run tests with

```
$ rake test
```

## License

[MIT](LICENSE.txt)

[open-uri]: http://ruby-doc.org/stdlib-2.3.0/libdoc/open-uri/rdoc/OpenURI.html
[HTTP.rb]: https://github.com/httprb/http
[Addressable::URI]: https://github.com/sporkmonger/addressable
