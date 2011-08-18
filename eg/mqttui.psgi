#!/usr/bin/perl
use strict;
use warnings;
use Plack::App::MQTTUI;

my %args =
  (
   host => $ENV{MQTT_SERVER} || '127.0.0.1',
   allow_publish => 1,
  );
$args{topic_regexp} = $ENV{MQTT_TOPIC_REGEXP}
  if (exists $ENV{MQTT_TOPIC_REGEXP});
my $app = Plack::App::MQTTUI->new(%args)->to_app;
