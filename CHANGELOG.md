## HEAD

* Return empty string when length is zero in `ChunkedIO#read` and `ChunkedIO#readpartial` (@janko-m)

* Make `posix-spawn` optional (@janko-m)

## 4.4.0 (2018-04-12)

* Add `:method` option to `Down::Http` for specifying the request method (@janko-m)

* Set default timeout of 30 for each operation to all backends (@janko-m)

## 4.3.0 (2018-03-11)

* Accept CLI arguments as a list of symbols in `Down::Wget#download` (@janko-m)

* Avoid potential URL parsing errors in `Down::Http::DownloadedFile#filename_from_url` (@janko-m)

* Make memory usage of `Down::Wget#download` constant (@janko-m)

* Add `:destination` option to `Down.download` for specifying download destination (@janko-m)

## 4.2.1 (2018-01-29)

* Reduce memory allocation in `Down::ChunkedIO` by 10x when buffer string is used (@janko-m)

* Reduce memory allocation in `Down::Http.download` by 10x.

## 4.2.0 (2017-12-22)

* Handle `:max_redirects` in `Down::NetHttp#open` and follow up to 2 redirects by default (@janko-m)

## 4.1.1 (2017-10-15)

* Raise all system call exceptions as `Down::ConnectionError` in `Down::NetHttp` (@janko-m)

* Raise `Errno::ETIMEDOUT` as `Down::TimeoutError` in `Down::NetHttp` (@janko-m)

* Raise `Addressable::URI::InvalidURIError` as `Down::InvalidUrl` in `Down::Http` (@janko-m)

## 4.1.0 (2017-08-29)

* Fix `FiberError` occurring on `Down::NetHttp.open` when response is chunked and gzipped (@janko-m)

* Use a default `User-Agent` in `Down::NetHttp.open` (@janko-m)

* Fix raw read timeout error sometimes being raised instead of `Down::TimeoutError` in `Down.open` (@janko-m)

* `Down::ChunkedIO` can now be parsed by the CSV Ruby standard library (@janko-m)

* Implement `Down::ChunkedIO#gets` (@janko-m)

* Implement `Down::ChunkedIO#pos` (@janko-m)

## 4.0.1 (2017-07-08)

* Load and assign the `NetHttp` backend immediately on `require "down"` (@janko-m)

* Remove undocumented `Down::ChunkedIO#backend=` that was added in 4.0.0 to avoid confusion (@janko-m)

## 4.0.0 (2017-06-24)

* Don't apply `Down.download` and `Down.open` overrides when loading a backend (@janko-m)

* Remove `Down::Http.client` attribute accessor (@janko-m)

* Make `Down::NetHttp`, `Down::Http`, and `Down::Wget` classes instead of modules (@janko-m)

* Remove `Down.copy_to_tempfile` (@janko-m)

* Add Wget backend (@janko-m)

* Add `:content_length_proc` and `:progress_proc` to the HTTP.rb backend (@janko-m)

* Halve string allocations in `Down::ChunkedIO#readpartial` when buffer string is not used (@janko-m)

## 3.2.0 (2017-06-21)

* Add `Down::ChunkedIO#readpartial` for more memory efficient reading (@janko-m)

* Fix `Down::ChunkedIO` not returning second part of the last chunk if it was previously partially read (@janko-m)

* Strip internal variables from `Down::ChunkedIO#inspect` and show only the important ones (@janko-m)

* Add `Down::ChunkedIO#closed?` (@janko-m)

* Add `Down::ChunkedIO#rewindable?` (@janko-m)

* In `Down::ChunkedIO` only create the Tempfile if it's going to be used (@janko-m)

## 3.1.0 (2017-06-16)

* Split `Down::NotFound` into explanatory exceptions (@janko-m)

* Add `:read_timeout` and `:open_timeout` options to `Down::NetHttp.open` (@janko-m)

* Return an `Integer` in `data[:status]` on a result of `Down.open` when using the HTTP.rb strategy (@janko-m)

## 3.0.0 (2017-05-24)

* Make `Down.open` pass encoding from content type charset to `Down::ChunkedIO` (@janko-m)

* Add `:encoding` option to `Down::ChunkedIO.new` for specifying the encoding of returned content (@janko-m)

* Add HTTP.rb backend as an alternative to Net::HTTP (@janko-m)

* Stop testing on MRI 2.1 (@janko-m)

* Forward cookies from the `Set-Cookie` response header when redirecting (@janko-m)

* Add `frozen-string-literal: true` comments for less string allocations on Ruby 2.3+ (@janko-m)

* Modify `#content_type` to return nil instead of `application/octet-stream` when `Content-Type` is blank in `Down.download` (@janko-m)

* `Down::ChunkedIO#read`, `#each_chunk`, `#eof?`, `rewind` now raise an `IOError` when `Down::ChunkedIO` has been closed (@janko-m)

* `Down::ChunkedIO` now caches only the content that has been read (@janko-m)

* Add `Down::ChunkedIO#size=` to allow assigning size after the `Down::ChunkedIO` has been instantiated (@janko-m)

* Make `:size` an optional argument in `Down::ChunkedIO` (@janko-m)

* Call enumerator's `ensure` block when `Down::ChunkedIO#close` is called (@janko-m)

* Add `:rewindable` option to `Down::ChunkedIO` and `Down.open` for disabling caching read content into a file (@janko-m)

* Drop support for MRI 2.0 (@janko-m)

* Drop support for MRI 1.9.3 (@janko-m)

* Remove deprecated `:progress` option (@janko-m)

* Remove deprecated `:timeout` option (@janko-m)

* Reraise only a subset of exceptions as `Down::NotFound` in `Down.download` (@janko-m)

* Support streaming of "Transfer-Encoding: chunked" responses in `Down.open` again (@janko-m)

* Remove deprecated `Down.stream` (@janko-m)

## 2.5.1 (2017-05-13)

* Remove URL from the error messages (@janko-m)

## 2.5.0 (2017-05-03)

* Support both Strings and `URI` objects in `Down.download` and `Down.open` (@olleolleolle)

* Work around a `CGI.unescape` bug in Ruby 2.4.

* Apply HTTP Basic authentication contained in URLs in `Down.open`.

* Raise `Down::NotFound` on 4xx and 5xx responses in `Down.open`.

* Write `:status` and `:headers` information to `Down::ChunkedIO#data` in `Down.open`.

* Add `#data` attribute to `Down::ChunkedIO` for saving custom result data.

* Don't save retrieved chunks into the file in `Down::ChunkedIO#each_chunk`.

* Add `:proxy` option to `Down.download` and `Down.open`.

## 2.4.3 (2017-04-06)

* Show the input URL in the `Down::Error` message.

## 2.4.2 (2017-03-28)

* Don't raise `StopIteration` in `Down::ChunkedIO` when `:chunks` is an empty
  Enumerator.

## 2.4.1 (2017-03-23)

* Correctly detect empty filename from `Content-Disposition` header, and
  in this case continue extracting filename from URL.

## 2.4.0 (2017-03-19)

* Allow `Down.open` to accept request headers as options with String keys,
  just like `Down.download` does.

* Decode URI-decoded filenames from the `Content-Disposition` header

* Parse filenames without quotes from the `Content-Disposition` header

## 2.3.8 (2016-11-07)

* Work around `Transfer-Encoding: chunked` responses by downloading whole
  response body.

## 2.3.7 (2016-11-06)

* In `Down.open` send requests using the URI *path* instead of the full URI.

## 2.3.6 (2016-07-26)

* Read #original_filename from the "Content-Disposition" header.

* Extract `Down::ChunkedIO` into a file, so that it can be required separately.

* In `Down.stream` close the IO after reading from it.

## 2.3.5 (2016-07-18)

* Prevent reading the whole response body when the IO returned by `Down.open`
  is closed.

## 2.3.4 (2016-07-14)

* Require `net/http`

## 2.3.3 (2016-06-23)

* Improve `Down::ChunkedIO` (and thus `Down.open`):

  - `#each_chunk` and `#read` now automatically call `:on_close` when all
    chunks were downloaded

  - `#eof?` had incorrect behaviour, where it would return true if
    everything was downloaded, instead only when it's also at the end of
    the file

  - `#close` can now be called multiple times, as the `:on_close` will always
    be called only once

  - end of download is now detected immediately when the last chunk was
    downloaded (as opposed to after trying to read the next one)

## 2.3.2 (2016-06-22)

* Add `Down.open` for IO-like streaming, and deprecate `Down.stream` (janko-m)

* Allow URLs with basic authentication (`http://user:password@example.com`) (janko-m)

## ~~2.3.1 (2016-06-22)~~ (yanked)

## ~~2.3.0 (2016-06-22)~~ (yanked)

## 2.2.1 (2016-06-06)

* Make Down work on Windows (martinsefcik)

* Close an internal file descriptor that was left open (martinsefcik)

## 2.2.0 (2016-05-19)

* Add ability to follow redirects, and allow maximum of 2 redirects by default (janko-m)

* Fix a potential Windows issue when extracting `#original_filename` (janko-m)

* Fix `#original_filename` being incomplete if filename contains a slash (janko-m)

## 2.1.0 (2016-04-12)

* Make `:progress_proc` and `:content_length_proc` work with `:max_size` (janko-m)

* Deprecate `:progress` in favor of open-uri's `:progress_proc` (janko-m)

* Deprecate `:timeout` in favor of open-uri's `:open_timeout` and `:read_timeout` (janko-m)

* Add `Down.stream` for streaming remote files in chunks (janko-m)

* Replace deprecated `URI.encode` with `CGI.unescape` in downloaded file's `#original_filename` (janko-m)

## 2.0.1 (2016-03-06)

* Add error message when file was to large, and use a simple error message for other generic download failures (janko-m)

## 2.0.0 (2016-02-03)

* Fix an issue where valid URLs were transformed into invalid URLs (janko-m)

  - All input URLs now have to be properly encoded, which should already be the
    case in most situations.

* Include the error class when download fails (janko-m)

## 1.1.0 (2016-01-26)

* Forward all additional options to open-uri (janko-m)

## 1.0.5 (2015-12-18)

* Move the open-uri file to the new location instead of copying it (janko-m)

## 1.0.4 (2015-11-19)

* Delete the old open-uri file after using it (janko-m)

## 1.0.3 (2015-11-16)

* Fix `#download` and `#copy_to_tempfile` not preserving the file extension (janko-m)

* Fix `#copy_to_tempfile` not working when given a nested basename (janko-m)

## 1.0.2 (2015-10-24)

* Fix Down not working with Ruby 1.9.3 (janko-m)

## 1.0.1 (2015-10-01)

* Don't allow redirects when downloading files (janko-m)
