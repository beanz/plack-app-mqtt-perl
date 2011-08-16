#!/usr/bin/perl
use strict;
use warnings;
use Plack::App::MQTT;

my $server = $ENV{MQTT_SERVER} || '127.0.0.1';
my $app = Plack::App::MQTT->new(host => $server, allow_publish => 1)->to_app;
