package AnyEvent::MQTT;
use strict;
use warnings;
use AnyEvent;
use Net::MQTT::Message;
use Net::MQTT::Constants;

sub new { bless { calls => [['new', @_]] }, 'AnyEvent::MQTT' }

sub calls { splice @{$_[0]->{calls}} }

sub subscribe {
  my $self = shift;
  push @{$self->{calls}} => ['subscribe', @_];
  my %p = @_;
  $p{callback}->($p{topic}, 'test',
                 Net::MQTT::Message->new(message_type => MQTT_PUBLISH,
                                         topic => $p{topic},
                                         message => 'test'));
}

sub unsubscribe {
  my $self = shift;
  push @{$self->{calls}} => ['unsubscribe', @_];
}

sub publish {
  my $self = shift;
  push @{$self->{calls}} => ['publish', @_];
  my $cv = AnyEvent->condvar;
  $cv->send(1);
  $cv;
}

sub cleanup {}

1;
