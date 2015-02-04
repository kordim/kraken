#!/usr/bin/perl  
$|=1;
use strict;
use Kraken::Channel;
use Kraken::Source;
use Kraken::Config;
use Kraken::Interface;
use Kraken::Kraken;


my $address = shift @ARGV || '172.26.2.124';
my $port    = shift @ARGV || '22222';

Kraken->add_channel('command');
Kraken->var('address'  , "$address");
Kraken->var('port'     , "$port");
Kraken->var('protocol' , 'tcp');
Kraken->open_channel();


print "Kraken started on $address:$port\n";
print "For more help run: \n";
print "echo \"help\" | nc $address $port\n";
Kraken->start_loop();
