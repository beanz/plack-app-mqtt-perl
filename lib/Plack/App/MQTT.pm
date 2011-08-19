use strict;
use warnings;
package Plack::App::MQTT;

# ABSTRACT: Plack Application to provide AJAX to MQTT bridge

=head1 SYNOPSIS

  use Plack::App::MQTT;
  my $app = Plack::App::MQTT->new(host => 'mqtt.example.com',
                                  allow_publish => 1)->to_app;

  # Or mount under /mqtt namespace, subscribe only
  use Plack::Builder;
  builder {
    mount '/mqtt' => Plack::App::MQTT->new();
  };

=head1 DESCRIPTION

This module is a Plack application that provides an AJAX to MQTT
bridge.  It can be used on its own or combined with L<Plack::Builder>
to provide an AJAX MQTT interface for existing Plack applications
(such as L<Catalyst>, L<Dancer>, etc applications).

This distribution includes an example application C<eg/mqttui.psgi>
that can be used for testing by running:

  MQTT_SERVER=127.0.0.1 plackup eg/mqttui.psgi

then accessing, for example:

  http://127.0.0.1:5000/?topic=test
  http://127.0.0.1:5000/?topic=test&mxhr=1

The former provides a simple long poll interface (that will often miss
messages - I plan to fix this) and the later provides a more reliable
"multipart/mixed" interface using the
L<DUI.Stream|http://about.digg.com/blog/duistream-and-mxhr> library.

=head1 API

This is an early release and the API is B<very> likely to change in
subsequent releases.

=head1 BUGS

This code has lots of bugs - multiple non-mxhr clients wont work, etc.

=head1 DISCLAIMER

This is B<not> official IBM code.  I work for IBM but I'm writing this
in my spare time (with permission) for fun.

=cut

use constant DEBUG => $ENV{PLACK_APP_MQTT_DEBUG};
use AnyEvent;
use AnyEvent::MQTT;
use Sub::Name;
use Scalar::Util qw/weaken/;
use parent qw/Plack::Component/;
use Plack::Util::Accessor qw/host port timeout keep_alive_timer client_id
                             topic_regexp allow_publish/;
use Plack::Request;
use JSON;
use MIME::Base64;

our %methods =
  (
   '/pub' => 'publish',
   '/sub' => 'subscribe',
   '/submxhr' => 'submxhr',
  );

=method C<new(%params)>

Constructs a new C<Plack::App::MQTT> object.  The supported parameters
are:

=over

=item C<host>

The server host.  Defaults to C<127.0.0.1>.

=item C<port>

The server port.  Defaults to C<1883>.

=item C<timeout>

The timeout for responses from the server.

=item C<keep_alive_timer>

The keep alive timer.

=item C<client_id>

Sets the client id for the client overriding the default which is
C<Net::MQTT::Message[NNNNN]> where NNNNN is the process id.

=item C<allow_publish>

If set to true, then the C<'/pub'> requests will be allowed.
Otherwise they will result in a '403 forbidden' response.  The default
is false.

=back

=cut

sub prepare_app {
  my $self = shift;
  my %args = ();
  foreach my $attr (qw/host port timeout keep_alive_timer client_id/) {
    my $v = $self->$attr;
    $args{$attr} = $v if (defined $v);
  }
  $self->{mqtt} = AnyEvent::MQTT->new(%args);
  $self->{topic_re} = qr!$self->{topic_regexp}!o
    if (defined $self->{topic_regexp});
}

=method C<call($env)>

This method routes HTTP requests to C</pub>, C</sub> and C</submxhr>
to the L</publish($env, $req, $topic)>, L</subscribe($env, $req,
$topic)>, or L</submxhr($env, $req, $topic)> methods respectively.

If the topic fails the L</is_valid_topic($topic)> test then a 403
error is returned.  If the request is C<'/pub'> then a 403 error is
returned unless the C<allow_publish> parameter was passed a true value
to the constructor.

=cut

sub call {
  my ($self, $env) = @_;
  die $self.' requires psgi.streaming support'
    unless ($env->{'psgi.streaming'});
  my $req = Plack::Request->new($env);
  my $path = $req->path_info;
  my $topic = $req->param('topic');
  return $self->return_403 unless ($self->is_valid_topic);
  my $method = $methods{$path} or return $self->return_404;
  return $self->return_403 if ($path eq '/pub' && !$self->allow_publish);
  return $self->$method($env, $req, $topic);
}

=method C<is_valid_topic($topic)>

This helper method returns true if the topic is valid.  If the
C<topic_regexp> parameter was passed to the constructor, then the
topic is valid if it matches that expression.  Otherwise any topic is
valid.

=cut

sub is_valid_topic {
  my ($self, $topic) = @_;
  !defined $topic || !defined $self->{topic_re} || $topic =~ $self->{topic_re}
}

=method C<return_404([$message])>

This helper method constructs a 404 response with the given message or
'not found' if no message is supplied.

=cut

sub return_404 {
  my ($self, $message) = @_;
  $message = 'not found' unless (defined $message);
  [404,
   ['Content-Type' => 'text/plain', 'Content-Length' => length $message],
   [$message]];
}

=method C<return_403([$message])>

This helper method constructs a 403 response with the given message or
'forbidden' if no message is supplied.

=cut

sub return_403 {
  my ($self, $message) = @_;
  $message = 'forbidden' unless (defined $message);
  [403,
   ['Content-Type' => 'text/plain', 'Content-Length' => length $message],
   [$message]];
}

=method C<publish($env, $req, $topic)>

This method processes HTTP requests to C</pub>.  It requires C<topic>
and C<message> parameters and returns the JSON '{ success: 1 }' when
the message has been published.

=cut

sub publish {
  my ($self, $env, $req, $topic) = @_;
  my $message = $req->param('message');
  my $mqtt = $self->{mqtt};
  return sub {
    my $respond = shift;
    print STDERR "Publishing: $topic => $message\n" if DEBUG;
    my $cv = $mqtt->publish(topic => $topic, message => $message);
    $cv->cb(sub {
              print STDERR "Published: $topic => $message\n" if DEBUG;
              _return_json($respond, { success => 1 });
            });
  };
}

=method C<subscribe($env, $req, $topic)>

This method processes HTTP requests to C</sub>.  It requires a
C<topic> parameter and returns the next MQTT message received on that
topic as a JSON record for the form:

  { type: 'mqtt_message', message: 'message', topic: 'topic' }

TODO: need to add per-client backlog to avoid missing messages

=cut

sub subscribe {
  my ($self, $env, $req, $topic) = @_;
  my $mqtt = $self->{mqtt};
  return sub {
    my $respond = shift;
    my $cb;
    $cb = sub {
      my ($topic, $message) = @_;
      print STDERR "Received: $topic => $message\n" if DEBUG;
      $mqtt->unsubscribe(topic => $topic, callback => $cb);
      _return_json($respond, _mqtt_record($topic, $message));
    };
    $mqtt->subscribe(topic => $topic, callback => $cb);
  };
}

sub _mqtt_record {
  my ($topic, $message) = @_;
  { type => 'mqtt_message', message => $message, topic => $topic, }
}

sub _return_json {
  my ($respond, $ref, $code) = @_;
  $code = 200 unless (defined $code);
  my $json = JSON::encode_json($ref);
  $respond->([200,
              ['Content-Type' => 'application/json',
               'Content-Length' => length $json],
              [$json]]);
}

=method C<submxhr($env, $req, $topic)>

This method processes HTTP requests to C</submxhr>.  It requires a
C<topic> parameter and returns a 'multipart/mixed' response with a
series of JSON records for the form:

  { type: 'mqtt_message', message: 'message', topic: 'topic' }

=cut

sub submxhr {
  my ($self, $env, $req, $topic) = @_;
  my $mqtt = $self->{mqtt};
  my $boundary = _mxhr_boundary();
  return sub {
    my $respond = shift;
    my $writer =
      $respond->([200,
                  ['Content-Type'=>'multipart/mixed; boundary="'.$boundary.'"'],
                 ]);
    $writer->write('--'.$boundary."\n");
    my $cb;
    $cb = sub {
      my ($topic, $message) = @_;
      print STDERR "Received: $topic => $message\n" if DEBUG;
      $writer->write("Content-Type: application/json\n\n".
                     JSON::encode_json(_mqtt_record($topic, $message)).
                     "\n--".$boundary."\n");
    };
    $mqtt->subscribe(topic => $topic, callback => $cb);
  };
}

sub _mxhr_boundary { # copied from Tatsumaki/Handler.pm
  my $size = 2;
  my $b = MIME::Base64::encode(join('', map chr(rand(256)), 1..$size*3), '');
  $b =~ s/[\W]/X/g;  # ensure alnum only
  $b;
}

sub DESTROY {
  $_[0]->{mqtt}->cleanup if (defined $_[0]->{mqtt});
}

1;
