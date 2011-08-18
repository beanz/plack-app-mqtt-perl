use strict;
use warnings;
package Plack::App::MQTTUI;

# ABSTRACT: Plack Application to provide simple UI for AJAX to MQTT bridge

=head1 SYNOPSIS

  use Plack::App::MQTTUI;
  my $app = Plack::App::MQTTUI->new(host => 'mqtt.example.com',
                                    allow_publish => 1)->to_app;

  # Or mount under /mqtt namespace, subscribe only
  use Plack::Builder;
  builder {
    mount '/mqtt' => Plack::App::MQTTUI->new();
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
use parent qw/Plack::App::MQTT/;
use Text::MicroTemplate;

my %inline_data;
my $f;
while (<DATA>) {
  if (/^==== (\S+) ====$/) {
    $f = $1;
  } elsif (defined $f) {
    $inline_data{$f} .= $_;
  }
}
our %static;
our %template;
foreach my $f (keys %inline_data) {
  my $content = delete $inline_data{$f};
  if ($content =~ /^\?/) {
    $template{$f} = $content;
  } else {
    $static{$f} = $content;
  }
}

=method C<call($env)>

This method responds to HTTP requests for C<'/'>, C<'/js/DUI.js'> and
C<'/js/Stream.js'> and delegates handling of other requests to the
L<Plack::App::MQTT/call($env)> method.

=cut

sub call {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);
  my $path = $req->path_info;
  my $topic = $req->param('topic');
  return $self->_return_403 unless ($self->is_valid_topic);
  return $self->_static($env, $req, $path, $topic) if (exists $static{$path});
  return $self->_template($env, $req, $path, $topic)
    if (exists $template{$path});
  return $self->SUPER::call($env);
}

sub _static {
  my ($self, $env, $req, $page, $topic) = @_;
  my $data = $static{$page};
  return [200,
          ['Content-Type' => 'text/javascript', # TOFIX: allow non-js?
           'Content-Length' => length $data],
          [$data]];
}

sub _template {
  my ($self, $env, $req, $page, $topic) = @_;
  my $html =
    $self->_page_renderer($page)->($self, $env, $req, $topic)->as_string;
  return [200,
          ['Content-Type' => 'text/html', 'Content-Length' => length $html],
          [$html]];
}

sub _page_renderer {
  my ($self, $page) = @_;
  return $self->{renderer}->{$page} if (exists $self->{renderer}->{$page});
  my $template = $template{$page};
  $self->{renderer}->{$page} = Text::MicroTemplate::build_mt($template);
}

1;

__DATA__
==== / ====
? my ($self, $env, $req, $topic) = @_;
? my $allow_pub = $self->allow_publish;
? my $mxhr = $req->param('mxhr');
? my $ver = $Plack::App::MQTT::VERSION ? '/'.$Plack::App::MQTT::VERSION : '';
<html>
<head>
  <title>MQTT <?= $topic ?></title>
  <script src="http://www.google.com/jsapi"></script>
  <script type="text/javascript"> google.load("jquery", "1.6"); </script>
? if ($mxhr) {
  <script src="/js/DUI.js"></script>
  <script src="/js/Stream.js"></script>
? }
  <script type="text/javascript">
? if ($allow_pub) {
    function doPublish(pubtopic, pubmessage) {
      var message = pubmessage.attr('value');
      if (!message) return;
      var topic = pubtopic.attr('value') || '<?= $topic ?>';
      $.ajax({
        url: "pub",
        data: { topic: topic, message: message },
        type: 'post',
        dataType: 'json',
        success: function(r) { }
      });
      pubmessage.attr('value', '');
      return;
    };
? }
    function addMQTTmessage(msg) {
      var tid = msg.topic.replace(/"/g, '#');
      var sel = $('#messages td[topic="'+tid+'"]');
      if (sel.length) {
        sel.addClass('new').text(msg.message);
        var timer =
          setTimeout(function(){
                       sel.removeClass('new');
                       clearTimeout(timer);
                     }, 500);
      } else {
        var topic_text = msg.topic;
        var topic = $('<th/>').addClass('topic').text(topic_text);
        var text = $('<td/>').attr('topic', tid)
                             .addClass('text').text(msg.message);
        var row = $('<tr/>').addClass('mqtt-message').addClass('new')
                            .append(topic).append(text);
        var added = 0;
        $('#messages').find('tr').each(function() {
          var t = $(this).find('th').text();
          if (t >= topic_text) {
            $(this).before(row);
            added = 1;
            return false;
          }
        });
        if (added == 0) {
          $('#messages tbody').append(row);
        }
        var timer =
          setTimeout(function(){
                       row.removeClass('new');
                       clearTimeout(timer);
                     }, 500);
      }
    };
    function receiveMQTTmessage() {
      $.ajax({
              type: "GET",
              url: "sub?topic=" + escape("<?= $topic ?>"),
              cache: false,
              error: function(xhr, status, error) {
                setTimeout("receiveMQTTmessage()", 20000);
              },
              success: function(msg) {
                addMQTTmessage(msg);
                receiveMQTTmessage();
              }});
    };
    $(document).ready(function(){
      if (typeof DUI != 'undefined') {
        var s = new DUI.Stream();
        s.listen('application/json', function(payload) {
          var msg = eval('(' + payload + ')');
          addMQTTmessage(msg);
        });
        s.load("submxhr?topic=" + escape("<?= $topic ?>"));
      } else {
        receiveMQTTmessage();
      }
    });
  </script>
<style>
.new { color: red; }
#footer { clear: both; text-align: center; padding-top: 2em }
</style>
</head>
<body>
<h1>MQTT <?= $topic ?></h1>
? if ($allow_pub) {
<!-- move this input out of form so Firefox can submit with enter key :/ -->
Topic (for publish): <input id="pubtopic" name="pubtopic"
                             type="text" size="48" />
<form onsubmit="doPublish($('#pubtopic'), $('#pubmessage')); return false">
Message: <input id="pubmessage" type="text" size="48"/>
</form>
? }
<table border="1" id="messages"><tbody></tbody></table>

<div id="footer">Powered by <a
  href="http://github.com/beanz/plack-app-mqtt-perl"
  >Plack::App::MQTT<?= $ver ?></a>.</div>

</body>
</html>
==== /js/DUI.js ====
/**
 * DUI: The Digg User Interface Library
 *
 * Copyright (c) 2008-2009, Digg, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - Neither the name of the Digg, Inc. nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * @module DUI
 * @author Micah Snyder <micah@digg.com>
 * @description The Digg User Interface Library
 * @version 0.0.5
 * @link http://code.google.com/p/digg
 *
 */

/* Add Array.prototype.indexOf -- Guess which major browser doesn't support it natively yet? */
[].indexOf || (Array.prototype.indexOf = function(v, n){
    n = (n == null) ? 0 : n; var m = this.length;

    for(var i = n; i < m; i++) {
        if(this[i] == v) return i;
    }

    return -1;
});

(function($) {

/* Create our top-level namespace */
DUI = {};

/**
 * @class Class Class creation and management for use with jQuery. Class is a singleton that handles static and dynamic classes, as well as namespaces
 */
DUI.Class = {
    /**
     * @var {Array} _dontEnum Internal array of keys to omit when looking through a class' properties. Once the real DontEnum bit is writable we won't have to deal with this.
     */
    _dontEnum: ['_ident', '_dontEnum', 'create', 'namespace', 'ns', 'supers', 'sup', 'init', 'each'],

    /**
     * @function create Make a class! Do work son, do work
     * @param {optional Object} methods Any number of objects can be passed in as arguments to be added to the class upon creation
     * @param {optional Boolean} static If the last argument is Boolean, it will be treated as the static flag. Defaults to false (dynamic)
     */
    create: function() {
        //Set _this to DUI.Class
        var _this = this;

        //Figure out if we're creating a static or dynamic class
        var s = (arguments.length > 0 && //if we have arguments...
                arguments[arguments.length - 1].constructor == Boolean) ? //...and the last one is Boolean...
                    arguments[arguments.length - 1] : //...then it's the static flag...
                    false; //...otherwise default to a dynamic class

        //Static: Object, dynamic: Function
        var c = s ? {} : function() {
            this.init.apply(this, arguments);
        }

        //All of our classes have these in common
        var methods = {
            _ident: {
                library: "DUI.Class",
                version: "0.0.5",
                dynamic: true
            },

            //_dontEnum should exist in our classes as well
            _dontEnum: this._dontEnum,

            //A basic namespace container to pass objects through
            ns: [],

            //A container to hold one level of overwritten methods
            supers: {},

            //A constructor
            init: function() {},

            //Our namespace function
            namespace:function(ns) {
                //Don't add nothing
                if (!ns) return null;

                //Set _this to the current class, not the DUI.Class lib itself
                var _this = this;

                //Handle ['ns1', 'ns2'... 'nsN'] format
                if(ns.constructor == Array) {
                    //Call namespace normally for each array item...
                    $.each(ns, function() {
                        _this.namespace.apply(_this, [this]);
                    });

                    //...then get out of this call to namespace
                    return;

                //Handle {'ns': contents} format
                } else if(ns.constructor == Object) {
                    //Loop through the object passed to namespace
                    for(var key in ns) {
                        //Only operate on Objects and Functions
                        if([Object, Function].indexOf(ns[key].constructor) > -1) {
                            //In case this.ns has been deleted
                            if(!this.ns) this.ns = [];

                            //Copy the namespace into an array holder
                            this.ns[key] = ns[key];

                            //Apply namespace, this will be caught by the ['ns1', 'ns2'... 'nsN'] format above
                            this.namespace.apply(this, [key]);
                        }
                    }

                    //We're done with namespace for now
                    return;
                }

                //Note: [{'ns': contents}, {'ns2': contents2}... {'nsN': contentsN}] is inherently handled by the above two cases

                var levels = ns.split(".");

                /* Dynamic classes are Functions, so we'll extend their prototype.
                   Static classes are Objects, so we'll extend them directly */
                var nsobj = this.prototype ? this.prototype : this;

                $.each(levels, function() {
                    /* When adding a namespace check to see, in order:
                     * 1) Does the ns exist in our ns passthrough object?
                     * 2) Does the ns already exist in our class
                     * 3) Does the ns exist as a global var?
                     *    NOTE: Support for this was added so that you can namespace classes
                     *    into other classes, i.e. MyContainer.namespace('MyUtilClass'). this
                     *    behaviour is dangerously greedy though, so it may be removed.
                     * 4) If none of the above, make a new static class
                     */
                    nsobj[this] = _this.ns[this] || nsobj[this] || window[this] || DUI.Class.create(true);

                    /* If our parent and child are both dynamic classes, copy the child out of Parent.prototype and into Parent.
                     * It seems weird at first, but this allows you to instantiate a dynamic sub-class without instantiating
                     * its parent, e.g. var baz = new Foo.Bar();
                     */
                    if(_this.prototype && DUI.isClass(nsobj[this]) && nsobj[this].prototype) {
                        _this[this] = nsobj[this];
                    }

                    //Remove our temp passthrough if it exists
                    delete _this.ns[this];

                    //Move one level deeper for the next iteration
                     nsobj = nsobj[this];
                });

                //TODO: Do we really need to return this? It's not that useful anymore
                return nsobj;
            },

            /* Create exists inside classes too. neat huh?
             * Usage differs slightly: MyClass.create('MySubClass', { myMethod: function() }); */
            create: function() {
                //Turn arguments into a regular Array
                var args = Array.prototype.slice.call(arguments);

                //Pull the name of the new class out
                var name = args.shift();

                //Create a new class with the rest of the arguments
                var temp = DUI.Class.create.apply(DUI.Class, args);

                //Load our new class into the {name: class} format to pass it into namespace()
                var ns = {};
                ns[name] = temp;

                //Put the new class into the current one
                this.namespace(ns);
            },

            //Iterate over a class' members, omitting built-ins
            each: function(cb) {
                if(!$.isFunction(cb)) {
                    throw new Error('DUI.Class.each must be called with a function as its first argument.');
                }

                //Set _this to the current class, not the DUI.Class lib itself
                var _this = this;

                $.each(this, function(key) {
                    if(_this._dontEnum.indexOf(key) != -1) return;

                    cb.apply(this, [key, this]);
                });
            },

            //Call the super of a method
            sup: function() {
                try {
                    var caller = this.sup.caller.name;
                    this.supers[caller].apply(this, arguments);
                } catch(noSuper) {
                    return false;
                }
            }
        }

        //Static classes don't need a constructor
        s ? delete methods.init : null;

        //...nor should they be identified as dynamic classes
        s ? methods._ident.dynamic = false : null;

        /* Put default methods into the class before anything else,
         *   so that they'll be overwritten by the user-specified ones */
        $.extend(c, methods);

        /* Second copy of methods for dynamic classes: They get our
         * common utils in their class definition AND their prototype */
        if(!s) $.extend(c.prototype, methods);

        //Static: extend the Object, Dynamic: extend the prototype
        var extendee = s ? c : c.prototype;

        //Loop through arguments. If they're the right type, tack them on
        $.each(arguments, function() {
            //Either we're passing in an object full of methods, or the prototype of an existing class
            if(this.constructor == Object || typeof this.init != undefined) {
                /* Here we're going per-property instead of doing $.extend(extendee, this) so that
                 * we overwrite each property instead of the whole namespace. Also: we omit the 'namespace'
                 * helper method that DUI.Class tacks on, as there's no point in storing it as a super */
                for(i in this) {
                    /* If a property is a function (other than our built-in helpers) and it already exists
                     * in the class, save it as a super. note that this only saves the last occurrence */
                    if($.isFunction(extendee[i]) && _this._dontEnum.indexOf(i) == -1) {
                        //since Function.name is almost never set for us, do it manually
                        this[i].name = extendee[i].name = i;

                        //throw the existing function into this.supers before it's overwritten
                        extendee.supers[i] = extendee[i];
                    }

                    //Special case! If 'dontEnum' is passed in as an array, add its contents to DUI.Class._dontEnum
                    if(i == 'dontEnum' && this[i].constructor == Array) {
                        extendee._dontEnum = $.merge(extendee._dontEnum, this[i]);
                    }

                    //extend the current property into our class
                    extendee[i] = this[i];
                }
            }
        });

        //Shiny new class, ready to go
        return c;
    }
};

/* Turn DUI into a static class whose contents are DUI.
   Now you can use DUI's tools on DUI itself, i.e. DUI.create('Foo');
   I'm pretty sure this won't melt the known universe, but caveat emptor. */
DUI = DUI.Class.create(DUI, true);

})(jQuery);

//Simple check so see if the object passed in is a DUI Class
DUI.isClass = function(check, type)
{
    type = type || false;

    try {
        if(check._ident.library == 'DUI.Class') {
            if((type == 'dynamic' && !check._ident.dynamic)
               || (type == 'static' && check._ident.dynamic)) {
                return false;
            }

            return true;
        }
    } catch(noIdentUhOh) {
        return false;
    }

    return false;
}
==== /js/Stream.js ====
/**
 * DUI.Stream: A JavaScript MXHR client
 *
 * Copyright (c) 2009, Digg, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - Neither the name of the Digg, Inc. nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * @module DUI.Stream
 * @author Micah Snyder <micah@digg.com>
 * @author Jordan Alperin <alpjor@digg.com>
 * @description A JavaScript MXHR client
 * @version 0.0.3
 * @link http://github.com/digg/dui
 *
 */
(function($) {
DUI.create('Stream', {
    pong: null,
    lastLength: 0,
    streams: [],
    listeners: {},

    init: function() {

    },

    load: function(url) {
        //These versions of XHR are known to work with MXHR
        try { this.req = new ActiveXObject('MSXML2.XMLHTTP.6.0'); } catch(nope) {
            try { this.req = new ActiveXObject('MSXML3.XMLHTTP'); } catch(nuhuh) {
                try { this.req = new XMLHttpRequest(); } catch(noway) {
                    throw new Error('Could not find supported version of XMLHttpRequest.');
                }
            }
        }

        //These versions don't support readyState == 3 header requests
        //try { this.req = new ActiveXObject('Microsoft.XMLHTTP'); } catch(err) {}
        //try { this.req = new ActiveXObject('MSXML2.XMLHTTP.3.0'); } catch(err) {}

        this.req.open('GET', url, true);

        var _this = this;
        this.req.onreadystatechange = function() {
            _this.readyStateNanny.apply(_this);
        }

        this.req.send(null);
    },

    readyStateNanny: function() {
        if(this.req.readyState == 3 && this.pong == null) {
            var contentTypeHeader = this.req.getResponseHeader("Content-Type");

            if(contentTypeHeader.indexOf("multipart/mixed") == -1) {
                this.req.onreadystatechange = function() {
                    throw new Error('Send it as multipart/mixed, genius.');
                    this.req.onreadystatechange = function() {};
                }.bind(this);

            } else {
                this.boundary = '--' + contentTypeHeader.split('"')[1];

                //Start pinging
                this.pong = window.setInterval(this.ping.bind(this), 15);
            }
        }

        if(this.req.readyState == 4) {
            //var contentTypeHeader = this.req.getResponseHeader("Content-Type");

            //Stop the insanity!
            clearInterval(this.pong);

            //One last ping to clean up
            this.ping();

            if(typeof this.listeners.complete != 'undefined') {
                var _this = this;
                $.each(this.listeners.complete, function() {
                    this.apply(_this);
                });
            }
        }
    },

    ping: function() {
        var length = this.req.responseText.length;

        var packet = this.req.responseText.substring(this.lastLength, length);

        this.processPacket(packet);

        this.lastLength = length;
    },

    processPacket: function(packet) {
        if(packet.length < 1) return;

        //I don't know if we can count on this, but it's fast as hell
        var startFlag = packet.indexOf(this.boundary);

        var endFlag = -1;

        //Is there a startFlag?
        if(startFlag > -1) {
            if(typeof this.currentStream != 'undefined') {
            //If there's an open stream, that's an endFlag, not a startFlag
                endFlag = startFlag;
                startFlag = -1;
            } else {
            //No open stream? Ok, valid startFlag. Let's try find an endFlag then.
                endFlag = packet.indexOf(this.boundary, startFlag + this.boundary.length);
            }
        }

        //No stream is open
        if(typeof this.currentStream == 'undefined') {
            //Open a stream
            this.currentStream = '';

            //Is there a start flag?
            if(startFlag > -1) {
            //Yes
                //Is there an end flag?
                if(endFlag > -1) {
                //Yes
                    //Use the end flag to grab the entire payload in one swoop
                    var payload = packet.substring(startFlag, endFlag);
                    this.currentStream += payload;

                    //Remove the payload from this chunk
                    packet = packet.replace(payload, '');

                    this.closeCurrentStream();

                    //Start over on the remainder of this packet
                    this.processPacket(packet);
                } else {
                //No
                    //Grab from the start of the start flag to the end of the chunk
                    this.currentStream += packet.substr(startFlag);

                    //Leave this.currentStream set and wait for another packet
                }
            } else {
                //WTF? No open stream and no start flag means someone fucked up the output
                //...OR maybe they're sending garbage in front of their first payload. Weird.
                //I guess just ignore it for now?
            }
        //Else we have an open stream
        } else {
            //Is there an end flag?
            if(endFlag > -1) {
            //Yes
                //Use the end flag to grab the rest of the payload
                var chunk = packet.substring(0, endFlag);
                this.currentStream += chunk;

                //Remove the rest of the payload from this chunk
                packet = packet.replace(chunk, '');

                this.closeCurrentStream();

                //Start over on the remainder of this packet
                this.processPacket(packet);
            } else {
            //No
                //Put this whole packet into this.currentStream
                this.currentStream += packet;

                //Wait for another packet...
            }
        }
    },

    closeCurrentStream: function() {
        //Write stream. Not sure if we need this
        //this.streams.push(this.currentStream);

        //Get mimetype
        //First, ditch the boundary
        this.currentStream = this.currentStream.replace(this.boundary + "\n", '');

        /* The mimetype is the first line after the boundary.
           Note that RFC 2046 says that there's either a mimetype here or a blank line to default to text/plain,
           so if the payload starts on the line after the boundary, we'll intentionally ditch that line
           because it doesn't conform to the spec. QQ more noob, L2play, etc. */
        var mimeAndPayload = this.currentStream.split("\n");

        var mime = mimeAndPayload.shift().split('Content-Type:', 2)[1].split(";", 1)[0].replace(' ', '');

        //Better to have this null than undefined
        mime = mime ? mime : null;

        //Get payload
        var payload = mimeAndPayload.join("\n");

        //Try to fire the listeners for this mimetype
        var _this = this;
        if(typeof this.listeners[mime] != 'undefined') {
            $.each(this.listeners[mime], function() {
                this.apply(_this, [payload]);
            });
        }

        //Set this.currentStream = null
        delete this.currentStream;
    },

    listen: function(mime, callback) {
        if(typeof this.listeners[mime] == 'undefined') {
            this.listeners[mime] = [];
        }

        if(typeof callback != 'undefined' && callback.constructor == Function) {
            this.listeners[mime].push(callback);
        }
    }
});
})(jQuery);

//Yep, I still use this. So what? You wanna fight about it?
Function.prototype.bind = function() {
    var __method = this, object = arguments[0], args = [];

    for(i = 1; i < arguments.length; i++)
        args.push(arguments[i]);

    return function() {
        return __method.apply(object, args);
    }
}

/* GLOSSARY
    packet: the amount of data sent in one ping interval
    payload: an entire piece of content, contained between multipart boundaries
    stream: the data sent between opening and closing an XHR. depending on how you implement MHXR, that could be a while.
*/
