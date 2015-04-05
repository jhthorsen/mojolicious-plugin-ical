package Mojolicious::Plugin::Ical;

=head1 NAME

Mojolicious::Plugin::Ical - Generate .ical documents

=head1 VERSION

0.01

=head1 DESCRIPTION

L<Mojolicious::Plugin::Ical> is a L<Mojolicious> plugin for generating
L<iCalendar|http://www.kanzaki.com/docs/ical/> documents.

=head1 SYNOPSIS

=head2 Application

  use Mojolicious::Lite;
  plugin ical => {
    properties => {
      calscale      => "GREGORIAN"         # default GREGORIAN
      method        => "REQUEST",          # default PUBLISH
      prodid        => "-//ABC Corporation//NONSGML My Product//EN",
      version       => "1.0",              # default to 2.0
      x_wr_caldesc  => "Some description",
      x_wr_calname  => "My calender",
      x_wr_timezone => "EDT",              # default to timezone for localhost
    }
  };

C<properties> can also be passed as argument to L</reply.ical>:

  $c->reply->ical({ properties => {...}, events => [...] });

=head2 Controller

  sub ical {
    my $c = shift;
    $c->reply->ical({
      events => [
        {
          created       => $date,
          description   => $str,   # http://www.kanzaki.com/docs/ical/description.html
          dtend         => $date,
          dtstamp       => $date,  # UTC time format, defaults to "now"
          dtstart       => $date,
          last_modified => $date,  # defaults to "now"
          location      => $str,   # http://www.kanzaki.com/docs/ical/location.html
          sequence      => $int,   # default 0
          status        => $str,   # http://www.kanzaki.com/docs/ical/status.html
          summary       => $str,   # http://www.kanzaki.com/docs/ical/summary.html
          transp        => $str,   # default OPAQUE
          uid           => $str,   # default to md5 of the values @hostname
        },
        ...
      ],
    });
  }

=cut

use Mojo::Base 'Mojolicious::Plugin';
use POSIX         ();
use Sys::Hostname ();
use Text::vFile::asData;

our $VERSION = '0.01';

my $vfile = Text::vFile::asData->new;

=head1 HELPERS

=head2 reply.ical

  $c = $c->reply->ical({ events => [...], properties => {...} });

Will render a iCal document with the Content-Type "text/calender".

See L</Controller> for example code.

=head1 METHODS

=head2 register

Register L</reply.ical> helper.

=cut

sub register {
  my ($self, $app, $config) = @_;

  $self->{properties} = $config->{properties};
  $self->{properties}{calscale}     ||= 'GREGORIAN';
  $self->{properties}{method}       ||= 'PUBLISH';
  $self->{properties}{prodid}       ||= sprintf '-//%s//NONSGML %s//EN', Sys::Hostname::hostname, $app->moniker;
  $self->{properties}{version}      ||= '2.0';
  $self->{properties}{x_wr_caldesc} ||= '';
  $self->{properties}{x_wr_calname} ||= $app->moniker;
  $self->{properties}{x_wr_timezone} ||= POSIX::strftime('%Z', localtime);

  $app->helper('reply.ical' => sub { $self->_reply_ical(@_) });
}

sub _event_to_properties {
  my ($event, $defaults) = @_;
  my $properties = {};

  for my $k (keys %$event) {
    my $v = $event->{$k} //= '';
    my $p = $k;
    $p = uc $k && $p =~ s!_!i!g if $p =~ /^[a-z]/;
    $properties->{$p} = [{value => $event->{$k}}];
  }

  $properties->{dtstamp}  ||= $defaults->{now};
  $properties->{sequence} ||= 0;
  $properties->{transp}   ||= 'OPAQUE';
  $properties->{uid}      ||= sprintf '%s@%s', _md5($event), $defaults->{hostname};
  $properties;
}

sub _reply_ical {
  my ($self, $c, $data) = @_;
  my %properties = %{$data->{properties} || {}};
  my $ical = {};
  my %defaults;

  $ical->{objects}    = [];
  $ical->{properties} = {};
  $ical->{type}       = 'VCALENDAR';

  $properties{calscale}      ||= $self->{properties}{calscale};
  $properties{method}        ||= $self->{properties}{method};
  $properties{prodid}        ||= $self->{properties}{prodid};
  $properties{version}       ||= $self->{properties}{version};
  $properties{x_wr_caldesc}  ||= $self->{properties}{x_wr_caldesc};
  $properties{x_wr_calname}  ||= $self->{properties}{x_wr_calname};
  $properties{x_wr_timezone} ||= $self->{properties}{x_wr_timezone};

  for my $k (keys %properties) {
    my $p = $k;
    $p = uc $k && $p =~ s!_!i!g if $p =~ /^[a-z]/;
    $ical->{properties}{$p} = [{value => $properties{$k}}];
  }

  $defaults{hostname} = Sys::Hostname::hostname;
  $defaults{now}      = Mojo::Date->new->to_datetime;
  $defaults{now} =~ s![:-]!!g;    # 1994-11-06T08:49:37Z => 19941106T084937Z

  for my $event (@{$data->{events} || []}) {
    push @{$ical->{objects}}, {properties => _event_to_properties($event, \%defaults), type => 'VEVENT'};
  }

  $c->res->headers->content_type('text/calendar');
  $c->render(text => $vfile->generate_lines({objects => [$ical]}));
}

sub _md5 {
  my $data = $_[0];
  Mojo::Util::md5_sum(join ':', map {"$_=$data->{$_}"} grep { $_ ne 'dtstamp' } sort keys %$data);
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
