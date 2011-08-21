#!/usr/bin/perl
#
# Copyright (C) 2011 by Mark Hindess

use strict;
use warnings;
use Test::More tests => 20;
use lib 't/lib';
use Plack::Test;
use HTTP::Request::Common;
use JSON;

use_ok('Plack::App::MQTT');
my $component = Plack::App::MQTT->new(timeout => 5);
my $app = $component->to_app;
ok($app, 'created app');
test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/');
    is $res->code, '403', '/ returned "403"';
    is $res->content, 'forbidden', '... and content "forbidden"';
    is_deeply([$component->mqtt->calls],
              [['new' => 'AnyEvent::MQTT', timeout => 5]],
              '... correct mqtt calls');
  };

test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/?topic=test');
    is $res->code, '404', '/ returned "404"';
    is $res->content, 'not found', '... and content "not found"';
    is_deeply([$component->mqtt->calls], [], '... no mqtt calls');
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

is_deeply($component->return_403(
                        q{I'm sorry, Dave. I'm afraid I can't do that.}),
          [
           403,
           [
            'Content-Type',
            'text/plain',
            'Content-Length',
            44
           ],
           [
            'I\'m sorry, Dave. I\'m afraid I can\'t do that.'
           ]
          ],
          'test 403 w/message');

is_deeply($component->return_404(
                        q{These aren't the droids you're looking for.}),
          [
           404,
           [
            'Content-Type',
            'text/plain',
            'Content-Length',
            43
           ],
           [
            'These aren\'t the droids you\'re looking for.'
           ]
          ],
          'test 404 w/message');
