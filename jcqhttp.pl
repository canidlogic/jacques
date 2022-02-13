#!/usr/bin/env perl
package Jacques;

use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Inherit from forking Net::Server, which is a non-core dependency
#
use base qw(Net::Server::Fork);

# Other non-core dependencies
#
use HTTP::Request;
use JSON::Tiny qw(decode_json);

# Core dependencies
#
use File::Spec;

=head1 NAME

jcqhttp.pl - Simple local HTTP server

=head1 SYNOPSIS

  jcqhttp.pl 8080 website.json

=head1 DESCRIPTION

Runs an HTTP server on a local port so that a simple website can be run
over HTTP on the local machine.  Intended for static websites, or for
JavaScript webapps that exclusively use client-side scripting.  Jacques
does not have any server-side scripting support.

The first argument to the script must be a port number to set the HTTP
server up on localhost.  It must be in range [1024, 65535].

The second argument to the script is a JSON file that specifies the
website to serve.  This JSON file must be structured so that at the top
level it is a JSON object.  The property names of this object are
relative paths to the resource over HTTP, I<excluding> the opening
forward slash.  Property names must be a sequence of one or more
I<components> separated by forward slashes, with an optional forward
slash at the end of the sequence.  Components must be a sequence of one
or more ASCII lowercase letters, digits, underscores, hyphens and
periods, with the restriction that neither the first nor last character
may be a period, and no period may occur immediately after another
period.  HTTP path matching is case-insensitive.  As an exception, a
forward slash by itself C</> is also accepted as a property name,
referring to the resource to return when the root C</> of the HTTP
server is requested.

The values of each of these JSON properties must be arrays containing
two strings.  The first string is the MIME type to serve to the client
as the C<Content-Type> when this resource is requested.  The second
string is the path on the local file system to the file to serve when
this resource is requested.  Relative paths will be relative to the
directory containing the JSON file.

The JSON file is not actually loaded until a request is made to the
server.  Each request loads and parses the JSON file.  This means that a
change to the JSON file will immediately be reflected on all subsequent
requests without having to restart the Jacques server.  But since there
is no caching, this is inefficient if the JSON file is huge.  Jacques is
designed for relatively small websites.

All resources will be served with cache control of C<no-store>
indicating that no caching should be performed of any of the resources.
This allows website changes to be more reliably reflected when there are
many changes to the website as it is being served, which is the intended
use case of the Jacques server.

To stop the server, use the CTRL+C signal.

=cut

# =========
# Constants
# =========

# The chunk length in bytes to use as a buffer when transferring
# resource files to clients.
#
my $BUF_SIZE = 4096;

# ==========
# Local data
# ==========

# The path to the JSON configuration file.
#
# Set at the start of the program entrypoint.  Be sure this is an
# absolute path since the current working directory may be changed by
# the server!
#
my $json_path;

# ===============
# Local functions
# ===============

# Load the JSON file, and look up a given resource.
#
# If the resource is not found or there is a problem loading the JSON,
# (0, undef, undef) is returned.
#
# Otherwise, the return value is (1, $ctype, $cpath) where $ctype is the
# Content-Type value to return to the HTTP client for this resource and
# $cpath is an absolute path to the resource on the local file system.
#
# Parameters:
#
#   1 : string - the URI of the resource
#
# Return:
#
#   an array of three values:
#
#   1 : integer - 1 if resource found, 0 if not
#   2 : string of Content-Type value, or undef if resource not found
#   3 : string of resource path, or undef if resource not found
# 
sub find_resource {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameter as string
  my $uri = shift;
  $uri = "$uri";

  # URI must begin with "/"
  ($uri =~ /^\//) or return (0, undef, undef);
  
  # If URI is more than one character, drop the opening "/" else leave
  # it for the special "/"
  if (length($uri) > 1) {
    $uri = substr($uri, 1);
  }
  
  # Check that URI is valid according to our scheme, returning not found
  # if it is not
  if ($uri ne "/") {
    # If URI is not the special "/" then check that slash is not first
    # character
    (not ($uri =~ /^\//)) or return (0, undef, undef);
    
    # Also check that no slash immediately follows another slash
    (not ($uri =~ /\/\//)) or return (0, undef, undef);
    
    # Check that dot is not first character and never appears
    # immediately after a forward slash 
    (not ($uri =~ /^\./)) or return (0, undef, undef);
    (not ($uri =~ /\/\./)) or return (0, undef, undef);
    
    # Check that dot is not last character and never appears immediately
    # before a forward slash
    (not ($uri =~ /\.$/)) or return (0, undef, undef);
    (not ($uri =~ /\.\//)) or return (0, undef, undef);
    
    # Check that no dot immediately follows another dot
    (not ($uri =~ /\.\./)) or return (0, undef, undef);
    
    # Check that only characters are ASCII alphanumeric, underscore,
    # dot, hyphen, and forward slash, and that at least one character
    ($uri =~ /^[A-Za-z0-9_\.\-\/]+$/) or return (0, undef, undef);
  }
  
  # Normalize URI to lowercase
  $uri =~ tr/A-Z/a-z/;
  
  # Check that JSON file exists, returning not found if it doesn't
  (-f $json_path) or return (0, undef, undef);
  
  # Read the whole JSON file into a memory string in raw mode
  open(my $fhj, "< :raw", $json_path) or return (0, undef, undef);
  my $js;
  eval {
    local $/;
    $js = <$fhj>;
    close($fhj);
  };
  if ($@) {
    close($fhj);
    return (0, undef, undef);
  }

  # Parse the JSON and check that the top-level is a hash reference
  $js = decode_json($js);
  (ref($js) eq "HASH") or return (0, undef, undef);

  # If the requested URI is not a key in the hash, return not found
  (exists $js->{$uri}) or return (0, undef, undef);

  # Get the value the URI maps to in the JSON, and make sure it is an
  # array reference with length two
  my $val = $js->{$uri};
  (ref($val) eq "ARRAY") or return (0, undef, undef);
  ((scalar @$val) == 2) or return (0, undef, undef);

  # Get the record values for this URI from the JSON and make sure they
  # are not references, then set to strings
  my $val_ctype = $val->[0];
  my $val_cpath = $val->[1];

  ((not ref($val_ctype)) and (not ref($val_cpath))) or
    return (0, undef, undef);

  $val_ctype = "$val_ctype";
  $val_cpath = "$val_cpath";
  
  # Split the JSON path into volume, directory, filename
  (my $cvol, my $cdir, my $cnam) = File::Spec->splitpath($json_path);

  # Get the reference to the parent directory of the JSON file
  my $base_dir = File::Spec->catpath($cvol, $cdir, ".");
  
  # Resolve the content path, if necessary, against the JSON file path
  # to make it absolute
  $val_cpath = File::Spec->rel2abs($val_cpath, $base_dir);

  # Return the located resource information
  return (1, $val_ctype, $val_cpath);
}

# Called by the process_request handler whenever it has completed
# reading an HTTP message header block.
#
# The given parameter must have the whole message header block followed
# by the blank line at the end.
#
# If this function returns zero, then something was wrong with the
# headers and the HTTP request handler shouldn't try to process anything
# further on this connection.
#
# Parameters:
#
#   1 : string - the message header block and the blank line
#
# Return:
#
#   1 if caller can continue processing more request, 0 if not
#
sub handle_headers {
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameter as string
  my $str = shift;
  $str = "$str";
  
  # Only GET and HEAD are supported -- if any other kind, we just return
  # zero indicating server should close the connection
  (($str =~ /^GET[ \t]/i) or ($str =~ /^HEAD[ \t]/i)) or return 0;
  
  # Parse the HTTP request
  (my $r = HTTP::Request->parse($str)) or return 0;
  
  # By default, we will send the body; but if this was a HEAD request,
  # we should suppress the body
  my $send_body = 1;
  if ($r->method =~ /^HEAD$/i) {
    $send_body = 0;
  }

  # Look for the content-type value and the path to the file on the
  # local file system
  my $found_it;
  my $ctype;
  my $cpath;
  
  eval {
    ($found_it, $ctype, $cpath) = find_resource($r->uri);
  };
  if ($@) {
    $found_it = 0;
    $ctype = undef;
    $cpath = undef;
  }

  # Write resource response or error
  if ($found_it) {
    # We found the resource, so first start a flag indicating that
    # resource is ready
    my $ready = 1;
    
    # Check that resource path is regular file, else clear ready flag
    if ($ready) {
      (-f $cpath) or $ready = 0;
    }
    
    # stat the file and get the content length in bytes, clearing ready
    # flag if this doesn't work
    my $clen;
    if ($ready) {
      (undef,undef,undef,undef,undef,undef,undef,
        $clen,undef,undef,undef,undef,undef) = stat $cpath;
      
      (defined $clen) or $ready = 0;
    }
    
    # If we are ready at this point, we can write the headers; else,
    # write server error status
    if ($ready) {
      # All ready to go, so send headers
      print "HTTP/1.1 200 OK\r\n";
      print "Content-Type: $ctype\r\n";
      print "Content-Length: $clen\r\n";
      print "Cache-Control: no-store\r\n";
      print "\r\n";
      
    } else {
      # Found requested resource, but problem with it, so 500 and
      # return 1
      my $err_page = "HTTP 500: Internal Server Error\r\n";
      my $err_len = length($err_page);
      
      print "HTTP/1.1 500 Internal Server Error\r\n";
      print "Content-Type: text/plain\r\n";
      print "Content-Length: $err_len\r\n";
      print "Cache-Control: no-store\r\n";
      print "\r\n";
      
      if ($send_body) {
        print "$err_page";
      }
      
      return 1;
    }
    
    # If we got here but we are not sending the body, we are done
    if (not $send_body) {
      return 1;
    }
    
    # Open the file for reading in raw mode
    open(my $fhr, "< :raw", $cpath) or return 0;
    
    # Wrap rest in an eval block so file always gets closed on way out
    eval {
      
      my $buf = "";
      
      # Keep transferring while there are bytes left to read
      while ($clen > 0) {
        
        # Read length is the minimum of the remaining bytes and the
        # buffer size
        my $rlen = $clen;
        if ($rlen > $BUF_SIZE) {
          $rlen = $BUF_SIZE;
        }
        
        # Read that many bytes into the buffer; all should be present
        # unless the file changed, in which throw error
        (read($fhr, $buf, $rlen) == $rlen) or die "I/O error, stopped";
        
        # Print the bytes to the client
        (print { *STDOUT } $buf) or die "I/O error, stopped";
        
        # Decrease read size
        $clen = $clen - $rlen;
      }
    };
    if ($@) {
      close($fhr);
      return 0;
    }
    close($fhr);
  
  } else {
    # We didn't find the requested resource, so 404
    my $err_page = "HTTP 404: Not Found\r\n";
    my $err_len = length($err_page);
    
    print "HTTP/1.1 404 Not Found\r\n";
    print "Content-Type: text/plain\r\n";
    print "Content-Length: $err_len\r\n";
    print "Cache-Control: no-store\r\n";
    print "\r\n";
    
    if ($send_body) {
      print "$err_page";
    }
  }
  
  # If we got here, we're OK so we can handle more
  return 1;
}

# ====================
# HTTP request handler
# ====================

# Override the default echo handler to put our HTTP request handling
# code here.  CAUTION: this may be run from a forked process.
#
sub process_request {
  my $self = shift;
  
  # Since we only support GET and HEAD, the standard input stream will
  # be a sequence of HTTP request headers, each of which ends with an
  # empty line and doesn't contain any other empty lines; we therefore
  # can read line-by-line, buffer header lines, and then process the
  # buffer (and the final blank line) whenever we read a blank line
  my $lbuf = "";
  while (<STDIN>) {
    
    # Add the current line to the buffer, along with its line breaks
    $lbuf = $lbuf . $_;
    
    # If the current line is empty or contains nothing other than CR and
    # LF characters, then we just read a blank line so we can process
    # the message and clear the buffer
    if (/^[\r\n]*$/) {
      my $rstatus = eval {
        return handle_headers($lbuf);
      };
      if ($@) {
        return 0;
      }
      ($rstatus) or return 0;
      
      $lbuf = "";
    }
  }
}

# ==================
# Program entrypoint
# ==================

# Check parameter count
#
($#ARGV == 1) or die "Wrong number of parameters, stopped";

# Get the parameters and also remove them from the command-line
# parameters so that Net::Server will not try to scan them
#
my $arg_port  = shift(@ARGV);
   $json_path = shift(@ARGV);

# Parse the port and check it
#
($arg_port =~ /^[0-9]+$/) or die "Invalid port argument, stopped";

$arg_port = int($arg_port);

(($arg_port >= 1024) and ($arg_port <= 65535)) or
  die "Port number must be in range [1024, 65535], stopped";

# Convert the JSON path to an absolute path if necessary
#
$json_path = File::Spec->rel2abs($json_path);

# Get the effective user ID of this process
#
my $user_id = $>;

# Get the effective group ID of this process; if there are multiple
# groups, choose the first one, which is the effective group ID
#
my @groups = split " ", $);
($#groups >= 0) or die "Can't figure out effective group, stopped";
my $group_id = $groups[0];

# Start the server on the passed port and using the effective user ID
# and group ID; all requests will be handled by the process_request
# function defined earlier
#
Jacques->run(port => $arg_port, user => $user_id, group => $group_id);

=head1 AUTHOR

Noah Johnson, C<noah.johnson@loupmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 Multimedia Data Technology Inc.

MIT License:

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut

# End package with expression that evaluates to true
#
1;
