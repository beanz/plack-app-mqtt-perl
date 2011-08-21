#!/usr/bin/perl
#
# Copyright (C) 2011 by Mark Hindess

use strict;
use warnings;
use Test::More tests => 24;
use lib 't/lib';
use Plack::Test;
use HTTP::Request::Common;
use JSON;

use_ok('Plack::App::MQTTUI');
my $component = Plack::App::MQTTUI->new();
my $app = $component->to_app;
ok($app, 'created app');
test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/');
    is $res->code, '403', '/ returned "403"';
    is $res->content, 'forbidden', '... and content "forbidden"';
    is_deeply([$component->mqtt->calls], [['new' => 'AnyEvent::MQTT']],
              '... correct mqtt calls');
  };

test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/?topic=test');
    is $res->code, '200', '/?topic=test returned "200"';
    is $res->header('Content-Type'), 'text/html', '... and content-type html';
    is((substr $res->content, 0, 6), '<html>', '... and content "<html>..."');
    is_deeply([$component->mqtt->calls], [], '... correct mqtt calls');
  };

test_psgi # test with cached template renderer
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/?topic=test');
    is $res->code, '200', '/?topic=test returned "200"';
    is $res->header('Content-Type'), 'text/html', '... and content-type html';
    is((substr $res->content, 0, 6), '<html>', '... and content "<html>..."');
    is_deeply([$component->mqtt->calls], [], '... correct mqtt calls');
  };

test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/js/DUI.js');
    is $res->header('Content-Type'), 'text/javascript',
      '... and content-type javascript';
    is $res->code, '200', '/js/DUI.js returned "200"';
    is((substr $res->content, 0, 11), "/**\n * DUI:",
       '... and content "/**\n * DUI:..."');
    is_deeply([$component->mqtt->calls], [], '... correct mqtt calls');
  };

test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/js/Stream.js');
    is $res->header('Content-Type'), 'text/javascript',
      '... and content-type javascript';
    is $res->code, '200', '/js/Stream.js returned "200"';
    is((substr $res->content, 0, 17), "/**\n * DUI.Stream",
       '... and content "/**\n * DUI.Stream..."');
    is_deeply([$component->mqtt->calls], [], '... correct mqtt calls');
  };

test_psgi # test pass-thorough to parent
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
