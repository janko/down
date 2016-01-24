# Down

Down is a wrapper around `open-uri` for safe downloading of remote files.

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

## Features

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

### Progress

You can also tie into the progress of downloading, if you maybe want to display
a progress bar:

```rb
Down.download "http://example.com/image.jpg",
  progress: ->(size) { ... } # called on each chunk
```

### Download errors

Firstly, Down encodes unencoded URLs, `open-uri` will for example trip if the
URL has a space. There are a lot of ways that a download can fail:

* URL is really invalid (`URI::InvalidURIError`)
* URL is a little bit invalid, e.g. "http:/example.com" (`Errno::ECONNREFUSED`)
* Domain wasn't not found (`SocketError`)
* Domain was found, but status is 4xx or 5xx (`OpenURI::HTTPError`)
* Request went into a redirect loop (`RuntimeError`)
* Request timeout out (`Timeout::Error`)

Down unifies all of these errors, and simply throws `Down::NotFound` error
(because this is what actually happened from the outside perspective).

### Timeout

You can specify the time after the request will time out:

```rb
Down.download "http://example.com/image.jpg", timeout: 5
```

### Additional options

Any additional options will be forwarded to open-uri, so you can for example
add basic authentication:

```rb
Down.download "http://example.com/image.jpg", http_basic_authentication: ['john', 'secret']
```

### Copying to tempfile

Down has another "hidden" utility method, `#copy_to_tempfile`, which creates
a Tempfile out of the given file. The `#download` method uses it internally,
but it's also publicly available for direct use:

```rb
tempfile = Down.copy_to_tempfile "path/to/file.jpg"
tempfile.path #=> "/var/folders/k7/6zx6dx6x7ys3rv3srh0nyfj00000gn/T/down20151116-77262-jgcx65.jpg"
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
