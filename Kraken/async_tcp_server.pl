#!/usr/bin/perl -w
# Author: D. Korytsev (dkorytsev at gmail dot com)
# Aim: 
# $Id$
# Проверяю как работает recv и accept на сокет
# Не разделяю сокеты на акцептнутые и сокет к котором у коннектятся клиентыю
# Тупо для всех сокетов в массиве . делаю сначала recv а потом accept.
#
# Смысл этого такой. Если это udp сокет, то я сразу получу данные из него.
#
# Если это тсп сокет, то я попытаюсь получить из него данные и если не получитя, то акцептну от него новый сокет.
use diagnostics;
use strict;
{    package Config;
	my $ST_Config; # Singletone Config;
	sub new {
	    
	    if (not defined $ST_Config){
	        $ST_Config = bless {}, shift;
	    }
	
	    return $ST_Config;
	}
	
	sub var {
	    my $class = shift;
	    my $self = Config->new();
	
	    my $name = shift;
	    if (@_){
	        my $value = shift;
	        $self->{$name}=$value;
	        return 1;
	    }
	    return exists $self->{$name} ? $self->{$name} : undef;
	    
	}
1}

Config->var('protocol'=>'tcp');
Config->var('port'=>'22222');
Config->var('address'=>'172.26.2.124');


unless ( Config->var('bar') ){
    warn 'Bar not exists'
}

{ package Channel;

use IO::Socket;
use Socket qw/SOL_SOCKET SO_RCVBUF IPPROTO_TCP TCP_NODELAY/;
use Data::Dumper;

sub new {
      my $class = shift;
      my $self = bless {}, $class;
         $self->{io}='';
         $self->{sockets}={};
         $self->{queue}=();
      return $self
}
   
sub open{
    my $self = shift;
      
     my $socket =  IO::Socket::INET->new(
              LocalAddr => Config->var('address'), 
              LocalPort => Config->var('port'), 
              Proto     => Config->var('protocol'), 
              ReuseAddr => 1, 
              Listen    => SOMAXCONN,
     ) || die "$!";
      
    $self->add_socket( 'command' , $socket );
    $self->add_io( $socket );
}

sub var {
    my $self = shift;
    my $name = shift;
    if (@_){
        $self->{$name} = shift;
        return 1;
    }
    return $self->{$name}
}

sub add_socket {
    my $self = shift;
    my $addr = shift;
    if (@_){
        my $socket = shift;
        warn "add $addr " . $socket ."\n";
        $self->{sockets}->{$addr} = $socket;
        return 1;
    }
    return 0;
}
      
sub del_socket {
    my $self = shift;
    my $addr = shift;
    warn "delete $addr\n";
    delete $self->{sockets}->{$addr};
}

sub get_socket_list {
    my $self = shift;
    return wantarray ? values( %{ $self->{sockets} } ) : undef;
}

sub get_socket {
    my $self = shift;
    my $addr = shift;
    return $self->{sockets}->{$addr};
}

sub get_address {
    my $self   = shift;
    my $socket = shift;

    for my $address ( keys( %{ $self->{sockets} } ) ){
        my $r1 =  $socket;
        my $r2 =  $self->{sockets}->{$address};
        return $address if ($socket eq $self->{sockets}->{$address});
    }
}

sub add_queue {
    my $self = shift;
    my $source = shift;
    push @{ $self->{queue} } , $source ; # source;
    push @{ $self->{queue} } , shift ;   # data;
}

sub get_queue {
    my $self = shift;
    my $source = pop @{ $self->{queue} };
    my $data   = pop @{ $self->{queue} };

    return wantarray ? ($source,$data) : undef;
}

sub add_io{
    my $self = shift;
    my $socket = shift;
    vec($self->{io}, fileno($socket), 1 ) = 1;
}

sub del_io{
    my $self = shift;
    my $socket = shift;
    vec($self->{io}, fileno($socket), 1 ) = 0;
}


sub stop_loop {
    my $self = shift;
    $self->{loop}=0;
}
    
sub start_loop {
    my $self   = shift;
       $self->{loop} = 1;
    warn "Start loop\n";
    while ($self->{loop}){
        my ($ready_to_read) = select (my $rout=$self->{io}, undef, undef, 0);
        
        if ($ready_to_read){
            
            for my $socket ($self->get_socket_list() ){
                
                if ( vec ($rout, fileno($socket), 1) == 1  ) {
                    my $addr = $self->get_address($socket);
                    
                    my $recv_ret = $socket->recv(my $buffer, 8);

                    if (not defined $recv_ret){
                        # receive return error (try to accept from this socket);
                        warn "Try to accept...\n";
                        
                        my $new_io = $socket->accept();
                        my $far_sock_addr           = getpeername($new_io);
                        my ($far_port, $far_iaddr ) = sockaddr_in($far_sock_addr);
                        my $far_addr                = inet_ntoa($far_iaddr) . ":$far_port" ;
                        
                        $self->add_io($new_io);
                        $self->add_socket($far_addr, $new_io);            
                        print "Got Incoming Connection from $far_addr\n";
                        next;
                    }

                    # If socket is closed length of $buffer == 0. Need to close, and remove socket from $self->{io}
                    
                    if ($buffer eq '' ){ # ERROR
                        $self->del_io($socket);
                        $socket->close();
                        $self->del_socket($addr); 
                        print "Connection from $addr closed by client\n";
                        next; 
                    }
                    $self->add_queue($addr, $buffer);
                }
            }
        }else{
            my ($data, $source) = $self->get_queue();
            print "Processing task: $source -> $data\n" if ($source and $data);
        }
    }
}

1}



###############
my $channel = Channel->new();
   $channel->open();
   $channel->start_loop();
   print "LOOP FINISHED\n";
#####################
