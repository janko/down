## HEAD

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
