# Jacques

A simple, local HTTP server for static websites and client-side webapps.

This server is contained entirely within the `jcqhttp.pl` Perl script.  It's easy to use:

    jcqhttp.pl 8080 path/to/site.json

In this case, `8080` is the port on `localhost` to add the server to.  You can then view the website at the following URL:

    http://localhost:8080/

This server is only intended to be used on a local machine or personal LAN for offline use of webapps and testing webpages locally.  It is not secured for use on public networks.  For local use, you should only start on local ports in range [1024, 65535].

You may start on ports in range [0, 1023] only if you `sudo` the script so it runs as root.  __This is dangerous.__  It means that other computers beyond just the local box can access the HTTP server, and remember that Jacques is not secured for use on public networks!  This use is valid, however, if you are only going to be serving pages on a personal LAN.  You can use `ifconfig` to figure out the IP address of the local box.  Example return of `ifconfig`:

    eth0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
            ether 01:23:45:67:89:ab  txqueuelen 1000  (Ethernet)
            RX packets 0  bytes 0 (0.0 B)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 0  bytes 0 (0.0 B)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
            inet 127.0.0.1  netmask 255.0.0.0
            inet6 ::1  prefixlen 128  scopeid 0x10<host>
            loop  txqueuelen 1000  (Local Loopback)
            RX packets 2211  bytes 9808418 (9.3 MiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 2211  bytes 9808418 (9.3 MiB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 192.168.1.5  netmask 255.255.255.0  broadcast 192.168.1.255
            ether cd:ef:01:23:45:67  txqueuelen 1000  (Ethernet)
            RX packets 2512  bytes 1424774 (1.3 MiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 3130  bytes 2847507 (2.7 MiB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

The `eth0` entry refers to the Ethernet connection, which is not currently plugged in here.  The `lo` is a local loopback device.  The `wlan0` entry is the current wireless connection.  The `inet` field of `wlan0` is `192.168.1.5` which means that you can connect to this computer from other computers on the LAN at that address.  If you run `sudo jcqhttp.pl` on port `80` (the default HTTP port) on this machine, you can access the HTTP server on `http://192.168.1.5/` from other machines on the LAN.  If you already have an HTTP server running on that port, you may need to use a different port, in which case you would visit the site like `http://192.168.1.5:85/` on port 85, for example.  Only ports below 1024 will be accessible from other machines on the network.

Jacques will print a warning if you pass a port number below 1024.  The server will fail to start unless you are running it on root with `sudo`.

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
