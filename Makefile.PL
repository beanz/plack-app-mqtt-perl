
use strict;
use warnings;



use ExtUtils::MakeMaker 6.31;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'Plack Application to provide AJAX to MQTT bridge',
  'AUTHOR' => 'Mark Hindess <soft-cpan@temporalanomaly.com>',
  'BUILD_REQUIRES' => {
    'English' => '0',
    'HTTP::Request::Common' => '0',
    'Net::MQTT::Constants' => '0',
    'Net::MQTT::Message' => '0',
    'Plack::Test' => '0',
    'Test::More' => '0'
  },
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.31'
  },
  'DISTNAME' => 'Plack-App-MQTT',
  'EXE_FILES' => [],
  'LICENSE' => 'perl',
  'NAME' => 'Plack::App::MQTT',
  'PREREQ_PM' => {
    'AnyEvent' => '0',
    'AnyEvent::MQTT' => '1.112320',
    'JSON' => '0',
    'MIME::Base64' => '0',
    'Plack::Component' => '0',
    'Plack::Request' => '0',
    'Plack::Util::Accessor' => '0',
    'Scalar::Util' => '0',
    'Sub::Name' => '0',
    'Text::MicroTemplate' => '0',
    'constant' => '0',
    'parent' => '0'
  },
  'VERSION' => '1.112320',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



