#!/usr/bin/perl -wT
use strict;
#
# $Id: GBview.pl,v 1.5 2004/10/12 08:37:21 gellyfish Exp $
#
# USER CONFIGURATION SECTION
# --------------------------
# Modify these to your own settings, see the README file
# for detailed instructions.

use constant DEBUGGING      => 1;
use constant LIBDIR         => '.';
use constant CONFIG_ROOT    => '.';
use constant MAX_DEPTH      => 0;
use constant CONFIG_EXT     => '.trc';
use constant TEMPLATE_EXT   => '.trt';
use constant HTMLFILE_ROOT  => '';
use constant HTMLFILE_EXT   => '.html';
use constant CHARSET        => 'iso-8859-1';

# USER CONFIGURATION << END >>
# ----------------------------
# (no user serviceable parts beyond here)

=head1 NAME

GBview.pl - viewer script for a guestbook generated by TFmail.pl

=head1 DESCRIPTION

This CGI script reads a file in an XML-like format generated by
TFmail.pl, formats the data in the file using a template and
outputs it.

See the C<ADVANCED GUESTBOOK> section near the end of the
F<README> file for more details.

=cut

use Fcntl ':flock';
use CGI;
use lib LIBDIR;
use NMStreq;

BEGIN
{
  use vars qw($VERSION);
  $VERSION = substr q$Revision: 1.5 $, 10, -1;
}

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{PATH} =~ /(.*)/ and $ENV{PATH} = $1;

use vars qw($done_headers);
$done_headers = 0;

#
# We want to trap die() calls, output an error page and
# then do another die() so that the script aborts and the
# message gets into the server's error log.  If there is
# already a __DIE__ handler installed then we must
# respect it on our final die() call.
#
eval { local $SIG{__DIE__} ; main() };
if ($@)
{
   my $message = $@;
   error_page($message);
   die($message);
}

sub main
{
   my $treq = NMStreq->new(
      ConfigRoot    => CONFIG_ROOT,
      MaxDepth      => MAX_DEPTH,
      ConfigExt     => CONFIG_EXT,
      TemplateExt   => TEMPLATE_EXT,
      EnableUploads => 0,
      CGIPostMax    => 10000,
      Charset       => CHARSET,
   );

   if ( HTMLFILE_ROOT eq '' )
   {
      die "No HTMLFILE_ROOT set, nothing for this script to do\n";
   }

   my $htmlfile = $treq->config('gbview_htmlfile', 'guestbook');
   unless ( $htmlfile =~ /^([\w\-\/]+)$/ )
   {
      die "bad gbview_htmlfile value [$htmlfile] in config file";
   }
   $htmlfile = "@{[  HTMLFILE_ROOT ]}/$1@{[ HTMLFILE_EXT ]}";
    
   open LOCK, ">>$htmlfile.lck" or die "open >>$htmlfile.lck: $!";
   flock LOCK, LOCK_SH or die "flock $htmlfile.lck: $!";

   open IN, "<$htmlfile" or die "open $htmlfile: $!";
   my @entries;
   { local $/ = '</entry>' ; @entries = grep m#<entry>#, <IN> };
   close IN;

   close LOCK;

   unless ( $treq->config('gbview_oldest_first', 0) )
   {
      @entries = reverse @entries;
   }

   my $total = scalar @entries;

   my $startat = $treq->param('startat') || 0;
   $startat =~ /^(\d{1,4})$/ or die "bad startat value [$startat]\n";
   $startat = $1;
   splice @entries, 0, $startat;

   my $perpage = $treq->config('gbview_perpage', 0);
   $perpage =~ /^(\d{1,4})$/ or die "bad gbview_perpage value [$perpage] in config file\n";
   $perpage = $1;
   my ($page_count, $this_is_page) = (1, 1);
   if ($perpage > 0)
   {
      splice @entries, $perpage;
      $page_count   = int( ($total-1) / $perpage ) + 1;
      $this_is_page = int ( $startat / $perpage ) + 1;
   }

   $treq->install_foreach('entry', [map {extract_values($_)} @entries]);

   $treq->install_directive('can_go_back', ($startat > 0 ? 1 : 0));
   $treq->install_directive('can_go_on',   ($startat+$perpage <= $total-1 ? 1 : 0));
   $treq->install_directive('prev_page_start', $startat - $perpage);
   $treq->install_directive('next_page_start', $startat + $perpage);
   $treq->install_directive('page_count', $page_count);
   $treq->install_directive('this_is_page', $this_is_page);
   $treq->install_directive('multiple_pages', ($page_count > 1 ? 1 : 0) );

   $treq->install_foreach('page', [
      map {{  
         page  => $_,
         this  => ($_ == $this_is_page ? 1 : 0),
         start => ($_-1) * $perpage,
      }} (1..$page_count)
   ]);

   my $template = $treq->config('gbview_template', 'gbview');
   html_page($treq, $template);
}

=head1 INTERNAL FUNCTIONS

=over

=item extract_values ( STRING )

Converts a string consisting of named values encoded in an XML-like
format into a hashref.  The format is:

   <value name="$name">$value</value>

Where C<$name> and C<$value> are the strings that end up as keys and
values in the hash.  Stores a reference to the value rather than the
value itself, to prevent HTML metacharacters in the values from being
escaped when they're displayed via a template.  This is nessessary
to avoid double escaping, since HTML metacharacters were escaped by
TFmail.pl when the data was written to the file.

=cut

sub extract_values
{
   my ($string) = @_;

   my %hash;
   while ( $string =~ m#<value name="([\w\-\.\/]+)">(.*?)</value>#sg )
   {
      my ($key, $val) = ($1, $2);
      $hash{$key} = \$val;
   }

   return \%hash;
}
        
=item html_page ( TREQ, TEMPLATE )

Outputs an HTML page using the template TEMPLATE.

=cut

sub html_page
{
   my ($treq, $template) = @_;

   html_header();
   $done_headers = 1;

   $treq->process_template($template, 'html', \*STDOUT);
}

=item error_page ( MESSAGE )

Displays an "S<Application Error>" page, without using a
template since the error may have arisen during template
resolution.

=cut

sub error_page
{
   my ($message) = @_;

   unless ( $done_headers )
   {
      html_header();
      print <<EOERR;
<?xml version="1.0" encoding="@{[ CHARSET ]}"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>Error</title>
  </head>
  <body>
EOERR

      $done_headers = 1;
   }

   if ( DEBUGGING )
   {
      $message = NMSCharset->new(CHARSET)->escape($message);
      $message = "<p>$message</p>";
   }
   else
   {
      $message = '';
   }

   print <<EOERR;
    <h1>Application Error</h1>
    <p>
     An error has occurred in the program
    </p>
    $message
  </body>
</html>
EOERR
}

=item html_header ()

Outputs the CGI header using a content-type of text/html.

=cut

sub html_header {
    if ($CGI::VERSION >= 2.57) {
        # This is the correct way to set the charset
        print CGI::header('-type'=>'text/html', '-charset'=>CHARSET);
    }
    else {
        # However CGI.pm older than version 2.57 doesn't have the
        # -charset option so we cheat:
        print CGI::header('-type' => "text/html; charset=@{[ CHARSET ]}");
    }
}

=back

=head1 MAINTAINERS

The NMS project, E<lt>http://nms-cgi.sourceforge.net/E<gt>

To request support or report bugs, please email
E<lt>nms-cgi-support@lists.sourceforge.netE<gt>

=head1 COPYRIGHT

Copyright 2002 - 2004 London Perl Mongers, All rights reserved

=head1 LICENSE

This script is free software; you are free to redistribute it
and/or modify it under the same terms as Perl itself.

=cut

