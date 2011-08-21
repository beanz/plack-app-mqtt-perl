#!/usr/bin/perl
#
# Copyright (C) 2011 by Mark Hindess

use strict;
use warnings;
use Test::More tests => 9;
use lib 't/lib';
use Plack::Test;
use HTTP::Request::Common;
use JSON;

use_ok('Plack::App::MQTT');
my $component = Plack::App::MQTT->new(mqtt => AnyEvent::MQTT->new(),
                                      topic_regexp => '^zqk/');
is_deeply([$component->mqtt->calls], [['new' => 'AnyEvent::MQTT' ]],
          '... correct mqtt calls');
my $app = $component->to_app;
ok($app, 'created app');
test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/sub?topic=test');
    is $res->code, '403', '/sub?topic=test returned "403"';
    is($res->content, 'forbidden', '... and "forbidden"');
    is_deeply([$component->mqtt->calls], [], '... correct mqtt calls');
  };

test_psgi
  app => $app,
  client => sub {
    my $cb = shift;
    my $res = $cb->(GET '/sub?topic=zqk/test');
    is $res->code, '200', '/sub?topic=zqk/test returned "200"';
    is_deeply((decode_json $res->content),
              {
               type => 'mqtt_message',
               topic => 'zqk/test',
               message => 'test'
              },
              '... and some json');
    is_deeply([map { $_->[0] } $component->mqtt->calls],
              ['subscribe', 'unsubscribe'], '... correct mqtt calls');
  };
