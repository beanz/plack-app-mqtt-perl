#!/usr/bin/perl
#
# Copyright (C) 2011 by Mark Hindess

use strict;
use warnings;
use Test::More tests => 15;
use lib 't/lib';
use Plack::Test;
use HTTP::Request::Common;
use JSON;

use_ok('Plack::App::MQTT');
my $component = Plack::App::MQTT->new();
my $app = $component->to_app;
ok($app, 'created app');
test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/');
    is $res->code, '404', '/ returned "404"';
    is $res->content, 'not found', '... and content "not found"';
    is_deeply([$component->mqtt->calls],
              [['new' => 'AnyEvent::MQTT']], '... correct mqtt calls');
  };

test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/sub?topic=test');
    is $res->code, '200', '/sub?topic=test returned "200"';
    is_deeply((decode_json $res->content),
              {
               type => 'mqtt_message',
               topic => 'test',
               message => 'test'
              },
              '... and some json');
    is_deeply([map { $_->[0] } $component->mqtt->calls],
              ['subscribe', 'unsubscribe'], '... correct mqtt calls');
  };

test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/pub?topic=test&message=testing%201%202%203');
    is $res->code, '403', '/pub?topic=test&message=... returned "403"';
    is $res->content, 'forbidden', '... and content "forbidden"';
    is_deeply([$component->mqtt->calls], [], '... no mqtt calls');
  };

$component = Plack::App::MQTT->new(allow_publish => 1);
$app = $component->to_app;
ok($app, 'created app w/allow_publish');
test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/pub?topic=test&message=testing%201%202%203');
    is $res->code, '200', '/pub?topic=test&message=... returned "200"';
    is_deeply((decode_json $res->content),
              { success => 1 }, '... and some json');
    is_deeply([$component->mqtt->calls],
              [
               [
                'new' => 'AnyEvent::MQTT'
               ],
               [
                'publish',
                'topic' => 'test',
                'message' => 'testing 1 2 3'
               ]
              ], '... correct mqtt calls');
  };

