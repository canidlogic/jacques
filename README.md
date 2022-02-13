# Jacques

A simple, local HTTP server for static websites and client-side webapps.

This server is contained entirely within the `jcqhttp.pl` Perl script.  It's easy to use:

    jcqhttp.pl 8080 path/to/site.json

In this case, `8080` is the port on `localhost` to add the server to.  You can then view the website at the following URL:

    http://localhost:8080/

This server is only intended to be used on a local machine for offline use of webapps and testing webpages locally.  It is not secured for use on networks.  As such, you may only start on local ports in range [1024, 65535].

The other parameter is the path to a JSON file that describes the website the server should serve.  An example JSON file looks like this:

    {
      "/": ["text/html", "path/to/index.html"],
      "about.html": ["text/html", "path/to/about.html"],
      "logo.png": ["image/png", "path/to/logo.png"],
      "photo.jpg": ["image/jpeg", "path/to/photo.jpg"],
      "subdir/": ["text/html", "path/to/subdir/index.html"],
      "subdir/local.css": ["text/css", "path/to/subdir/local.css"]
    }

The property names of the top-level JSON object are the paths on the website to serve.  For example:

    Property: "subdir/local.css"
    URL:      http://localhost:8080/subdir/local.css

These paths are relative to the root directory, except for the special property name `/` which refers to the resource that is served when the root document of the web server is requested.  Paths must not start with a `/` (except for the special `/` path), but they may optionally end with `/`.  Path components are only allowed to use lowercase ASCII letters, digits, underscore, hyphen, and dot, and dot may neither be first nor last character of the component and you can't use two or more dots in a row.  Matching to paths is case-insensitive.

The values of each property in the top-level JSON object must be arrays of exactly two strings.  The first string is the MIME type to serve in the `Content-Type` header.  The second string is the path to the resource on the local file system.  Relative paths are resolved relative to the directory that contains the JSON file.

The server will reload the JSON file from the disk on every single request, and it will always include `Cache-Control` fields that indicate that no client caching should be used.  This is inefficient, but it allows the JSON file and any resource files to be updated at any time.  This is helpful for the intended use case of this server for offline testing.
