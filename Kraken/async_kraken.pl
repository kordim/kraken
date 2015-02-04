#!/usr/bin/perl -w 
# Author: D. Korytsev (dkorytsev at gmail dot com)
# Aim: 
# $Id$ Version 0.03

# открывает сконфигуренное количество каналов 
# слушает канал команд
# посылает данные из файлов в каналы
# может работать как в пакетном (HE) режиме так и в plain режиме отправляя по одной строке или пакету.


$|=1;
use strict;
use IO::Socket;
use IO::Socket::Multicast;
use Socket qw/SOL_SOCKET SO_RCVBUF IPPROTO_TCP TCP_NODELAY/;                                        
use Time::HiRes;
use Data::Dumper;
use XML::Simple;
use threads;
use threads::shared;

my $config_file = shift @ARGV;

die "Config file $config_file not readable" unless -r $config_file;
my $xml = XML::Simple->new();
my $data = $xml->XMLin($config_file, ForceArray => [ 'channel' ]);
my $config = $data->{channel};
my $command_port = $data->{command_port};
my $command_address = $data->{command_address};


{
package Kraken ;

use IO::Socket;
use IO::Socket::Multicast;
use Socket qw/SOL_SOCKET SO_RCVBUF IPPROTO_TCP TCP_NODELAY/;                                        
use IPC::Open2;

sub new{ bless{},shift }

sub add_channel {
  	my $self = shift;
	if (@_){
		my %options = @_;
		my $ch_name = $options{name};
          $self->{name}               = $ch_name;
		$self->{address}            = $options{address}            || die "ERROR: add_channel: address not defined\n ";
		$self->{port}               = $options{port}               || die "ERROR: add_channel: port not defined\n";
		if ($ch_name ne "command"){
            $self->{file}               = $options{file}               || die "ERROR: add_channel: file not defined\n"; 
          }
		$self->{mode}               = $options{mode}               || 'plain';
		$self->{protocol}           = $options{protocol}           || 'multicast_out';
		$self->{incoming_dump_file} = $options{incoming_dump_file} || "./$ch_name.in" ;
          $self->{EOF}                = 0;
		

          open $self->{incoming_dump_fh}, ">>$self->{incoming_dump_file}" || warn "Cannot open file for dumping $self->{incoming_dump_file} $!\n";

          if (defined $options{incoming_preprocessor}){
            $self->{incoming_preprocessor} = $options{incoming_preprocessor} ; 
	       $self->{incoming_preprocessor} =~ /^(\S+)(\s*?)(.*?)$/;
            my $in_preprocessor_bin = $1;
            if ( not -x $in_preprocessor_bin) {
		      warn "WARNING: File ".$in_preprocessor_bin." is not accessible to execute $!. /bin/cat will be used.\n";
		      delete $self->{incoming_preprocessor};
	           } 
            }
		
          if (defined $options{outgoing_preprocessor}){
            $self->{outgoing_preprocessor} = $options{outgoing_preprocessor} ;
	       $self->{outgoing_preprocessor} =~ /^(\S+)(\s*?)(.*?)$/;
	       my $out_preprocessor_bin = $1;
            if ( not -x $out_preprocessor_bin) {
		      warn "WARNING: File ".$out_preprocessor_bin." is not accessible to execute $!. /bin/cat will be used.\n";
		      delete $self->{outgoing_preprocessor};
	           } 
            }

	} else {
		die "ERROR: add_channel arguments not defined\n";
	}

	# Проверка существования и доступности файла с отсылаемыми данными
	if ($self->{name} ne 'command'){
        die "File ".$self->{file}." is not accessible to read $!\n" if ( not -r $self->{file} );	

     # открываем файл и сохраняем дескриптор
	open $self->{FH}, "<$self->{file}" || die "Cannot open self->{file} \n";
	binmode $self->{FH};
     print now()." INFO: Data file ". $self->{file} . " is opened\n";
     }
	
	
	# Создание сокета для отправки
	if ($self->{protocol} eq 'multicast_out'){
	     my $dest = $self->{address} . ":" . $self->{port};
		$self->{'socket'} = IO::Socket::Multicast->new(   ReuseAddr=>1,
                                                            PeerHost=>$self->{address}, 
                                                            PeerPort=>$self->{port});
		$self->{'socket'}->mcast_dest($dest);
    		$self->{'listener'} = IO::Socket::Multicast->new( ReuseAddr=>1,
                                                            LocalPort=>$self->{port}); 
		$self->{'listener'}->mcast_add($self->{address});
        } 
     elsif($self->{protocol} eq 'tcp_in'){
         $self->{socket} = IO::Socket::INET->new(LocalAddr=>$self->{address}, LocalPort => $self->{port}, Proto => 'tcp', ReuseAddr=>1 , Listen=>SOMAXCONN) or die "socket: $@";
     }
     elsif($self->{protocol} eq 'tcp_out'){
         $self->{socket} = IO::Socket::INET->new(PeerHost=>$self->{address}, PeerPort => $self->{port}, Proto => 'tcp') or die "socket: $@";
     }
     elsif($self->{protocol} eq 'tcp_in_out'){
         $self->{socket} = IO::Socket::INET->new(LocalAddr=>$self->{address}, LocalPort => $self->{port}, Proto => 'tcp', ReuseAddr=>1 , Listen=>SOMAXCONN) or die "socket: $@";
     }
     elsif($self->{protocol} eq 'udp_in'){
         $self->{socket} = IO::Socket::INET->new(LocalAddr=>$self->{address}, LocalPort => $self->{port}, Proto => 'udp') or die "socket: $@";
     }
     elsif($self->{protocol} eq 'udp_out'){
         $self->{socket} = IO::Socket::INET->new(PeerHost=>$self->{address}, PeerPort => $self->{port}, Proto => 'udp') or die "socket: $@";
     }
	return 1;
}

sub reopen {   
    my $self = shift;
    if ($self->{protocol} =~ /tcp_in/){
        warn "REOPEN TCP_IN connection\n";
        $self->{accept}->shutdown(2);
        $self->{socket}->shutdown(2);
        $self->{socket} = IO::Socket::INET->new(LocalAddr=>$self->{address}, LocalPort => $self->{port}, Proto => 'tcp', ReuseAddr=>1 , Listen=>SOMAXCONN) or die "socket: $@";
    }
}

sub var {
    my $self = shift;
    my $param = shift;
    if (@_) {
        $self->{$param} = $_[0];
        return 1;
    } else {
        return $self->{$param};
    }
}

sub send_data{
	my $self = shift;
     return if not $self->{packet_to_send};
	warn "INFO: send_data(): $self->{packet_to_send}\n";
     if ( $self->{protocol} eq 'multicast_out' ){
		$self->{'socket'}->mcast_send( $self->{packet_to_send} );
	}
     elsif ($self->{protocol} =~ /tcp(.+?)out/ ){
          $self->{'accept'}->send( $self->{packet_to_send} ) if $self->{'accept'};
     }
     elsif ( $self->{protocol} eq /udp_out/ ){
		$self->{'socket'}->send( $self->{packet_to_send});
     }
	$self->{packet_to_send}='';
}

	
sub dump_in{
    my $self = shift;
    print { $self->{incoming_dump_fh} } $self->now().$self->{incoming_buffer}."\n";
}

sub dump_out{
    my $self = shift;
    print { $self->{outgoing_dump_fh} } $self->now().$self->{outgoing_buffer}."\n";
}

sub skip_message{
	my $self = shift;
	$self->read_data();
}

sub goto_message{
	my $self  = shift;
	my $count = shift || return ;
	
	seek $self->{FH}, 0, 0;
     for my $i (0 .. $count ){
        $self->read_data();     
     }
}


sub now{
    my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime(time);
    $hour = sprintf("%02d",$hour);
    $min  = sprintf("%02d",$min);
    $sec  = sprintf("%02d",$sec);
    return "$hour:$min:$sec"
}

sub read_data {
    my $self = shift;
    $self->{packet_to_send}='';

    if ($self->{mode} eq 'packet' ){
        if (not read $self->{FH} , my $he_packet_size , 4){
            seek $self->{FH}, 0, 0;
            return;
        }
        else {
            $he_packet_size = unpack("l",$he_packet_size);
            read $self->{FH} , my $he_packet_timestamp , 8;
            read $self->{FH} , $self->{packet_to_send} , $he_packet_size; # если ничего не прочиталось, прыгаем в начало файла
            $self->{send_direction}='out';
        }
    } elsif ($self->{mode} eq 'plain' ){
        if (eof $self->{FH}){
            seek $self->{FH}, 0, 0;
            return;
        }
        else {
            $self->{packet_to_send} = readline $self->{FH};
        }
    } 
        
    return if not $self->{outgoing_preprocessor};
    
    my $pid = open2(my $exec_out, my $exec_in, $self->{outgoing_preprocessor}) || return $!;
    binmode $exec_in;
    binmode $exec_out;
   
    print $exec_in $self->{packet_to_send};
    $self->{packet_to_send}='';
    close $exec_in;
   
    while( sysread $exec_out, my $buffer, 64 ){ $self->{packet_to_send} .= $buffer ;}; 
    close $exec_out;
    waitpid($pid, 0);
}

sub list {
    my $self = shift;
    my @list = keys(%$self);
    print "---------------------\n";
    print join("\n",@list)."\n";
    print "---------------------\n";
    exit;
}
}1;


#############################################################################################
#
#	MAIN SECTION
#
#############################################################################################

# Создаем объекта каналов для отсылки. Настройки каналов берутся из структуры $config

my %channel_storage; 
my $rin='';
foreach my $channel_name (keys %{ $config }){
     my $tmp_kraken = Kraken->new();	
	   $tmp_kraken ->add_channel(	
		name                     => $channel_name,
		address                  => $config->{$channel_name}->{address},
		port                     => $config->{$channel_name}->{port},
		file                     => $config->{$channel_name}->{file},
		mode                     => $config->{$channel_name}->{mode},
		protocol                 => $config->{$channel_name}->{protocol},
		outgoing_preprocessor    => $config->{$channel_name}->{outgoing_preprocessor},
		incoming_preprocessor    => $config->{$channel_name}->{incoming_preprocessor},
	);
	
     $channel_storage{$channel_name}=$tmp_kraken;
     next if not defined $channel_storage{$channel_name}->var('socket');
     vec( $rin, fileno( $channel_storage{$channel_name}->var('socket') ), 1 ) = 1;
}


my $Kraken = $channel_storage{'ch1'};
   $Kraken->list();

my @command_queue;
while (1) {
   
   my ($found) = select(my $rout=$rin, undef,undef,0);
   
   if($found){
        foreach my $ch_name (keys %channel_storage){ 
            my $Kraken = $channel_storage{$ch_name};          
            my $socket = $Kraken->var('socket');
                    
            if ( $Kraken->var('protocol') =~ /tcp/){
                 my $accept = $Kraken->var('accept');
                 if ( vec($rout, fileno( $socket ),1 ) == 1 ){
                     
                     if ( not $accept ) {
                        warn "\t ACCEPT incoming connection\n";
                        my $new_accept = $socket->accept();
                        $Kraken->var('accept' , $new_accept );
	                   #vec($rin, fileno($socket),1 ) = 0 ;
	                   vec($rin, fileno($new_accept),1 ) = 1 ;
	                   warn "New Accept: ". fileno($new_accept) ."\n";
                        next;
                        }
                } elsif ( defined $accept and vec($rout,fileno($accept),1) == 1 ) { 
                    warn "INFO: Receive in accepted_socket\n";
                    my $len = $accept->recv(my $buf, 1024);
                    print "Len: '$len'\n";
                    if (not $buf){
                        sleep 1; 
	                   vec($rin, fileno($accept),1 ) = 0 ;
	                   vec($rin, fileno($socket),1 ) = 0 ;
                        $Kraken->reopen();
                        $socket = $Kraken->var('socket');
	                   vec($rin, fileno($socket),1 ) = 1 ;
                        warn "DDD\n";
                        next;
                    }
                    
                    push(@command_queue, $ch_name);
                    push(@command_queue, $buf);
	               }
            } elsif ( $Kraken->var('protocol') =~ /udp|multicast/ ) {
                if (vec($rout,fileno($socket),1) == 1) {
                    $socket->recv(my $buf,1024);
                    push(@command_queue, $ch_name);
                    push(@command_queue, $buf);
                    }
            }
        }
    } else { # Все буферы прочитаны можно проверить выполнение тасков в очереди
        
        #foreach my $thr ( threads->list(threads::joinable) ){
        #    my $ret = $thr->join();
        #    exit if  defined $ret and $ret eq 'exit';
        #}
        map {$_->join} (threads->list(threads::joinable));

        next if threads->list() >= 1;
        my $command      = pop(@command_queue);
        my $channel_name = pop(@command_queue);
        if (defined $command and defined $channel_name){
            print "$command $channel_name\n";
            my $thread = threads->create( \&process_command, $channel_name, $command, \%channel_storage);
            }
    }
}


sub process_command {
    my $channel_name    = shift;
    my $command         = shift;
    my $channel_storage = shift;
    print "process_command: $channel_name ->  $command\n";
    
    my $kraken = $$channel_storage{$channel_name};

    if ($channel_name ne 'command'){
        warn "INFO: received data from <$channel_name> : $command\n";
        $kraken->var('incoming_buffer',$command);
        $kraken->dump_in();
        
        #$kraken->preprocess('in');
        my $ready = $kraken->var('incoming_buffer');
        $kraken->var('packet_to_send', $ready);
        
        $kraken->send_data();
    
    } else {
        if ($command =~ /^send:/){
	       channel_send($command, $channel_storage);	
        }
	   elsif ($command =~ /^multisend:/){
	       channel_multisend($command, $channel_storage);	
	   }
        elsif($command =~ /^goto/){
            channel_goto($command, $channel_storage);
    	   }
        elsif($command =~ /^ch_list/){
            channel_list($channel_storage);
    	   }
        elsif($command =~ /^skip/){
            channel_skip($command,$channel_storage);
        }
        elsif($command =~ /^set/){
            channel_settings($command,$channel_storage);
        }
        elsif($command eq 'kill kraken'){
	       return 'exit'
	   }
    }
}



sub channel_settings {  # перебиараем список каналов и если в команде send встречается существующий канал, то шлем по нему очередную порцию данных
	my $command_message = shift;
	my $channel_storage = shift;
	chomp $command_message;
	$command_message =~ s/^set: //;
     my ($option, $channel_list) = split (" ", $command_message ,2);	
     $channel_list =~ s/\s//g;
	
     my %msg_ch_hash = map{split /:/,$_}(split /,/,$channel_list);

	foreach my $name (keys %{$channel_storage}){
          next unless (grep (/$name/, keys %msg_ch_hash)); # если указанного канала не существует в списке каналов то пропускаем
          my $value = $msg_ch_hash{$name};
          print "set $option fot channel: '$name'  value: '$value'\n";
          my $kraken = $$channel_storage{$name};
	     
          if ($option eq "rate"){
               $kraken->{options}->{rate}=$value
               }
          
          }
}
sub channel_multisend {  # перебиараем список каналов и если в команде send встречается существующий канал, то шлем по нему очередную порцию данных
	my $command_message = shift;
	my $channel_storage = shift;
	chomp $command_message;
	$command_message =~ s/^multisend: //;
	$command_message =~ s/\s//g;
	
     my %msg_ch_hash = map{split /:/,$_}(split /,/,$command_message);

     my @message_channel_list = split(/,/,$command_message);
	
	foreach my $name (keys %{$channel_storage}){
          next unless (grep (/$name/, keys %msg_ch_hash)); # если указанного канала не существует в списке каналов то пропускаем
          my $sending_count = $msg_ch_hash{$name};
          my $kraken = $$channel_storage{$name};
		
          if ($sending_count eq '*'){
                    while (! $kraken->{EOF} ){
                         sleep 1/$kraken->{options}->{rate} if exists $kraken->{options}->{rate};
                         $kraken->prepare_data_to_send();
		               $kraken->send_data();
                         }
                    $kraken->{EOF} = 0;
               }
          else {
               for (my $count=0 ; $count < $sending_count ; $count++){
                    sleep 1/$kraken->{options}->{rate} if exists $kraken->{options}->{rate};
                    $kraken->prepare_data_to_send();
		          $kraken->send_data();
                    }
               }
	
          }
}

sub channel_send {  # перебиараем список каналов и если в команде send встречается существующий канал, то шлем по нему очередную порцию данных
	my $command_message = shift;
	my $channel_storage = shift;
	chomp $command_message;
	$command_message =~ s/^send: //;
	$command_message =~ s/\s//g;
	my @message_channel_list = split(/,/,$command_message);
	
	foreach my $name (keys %{$channel_storage}){
		next unless (grep (/$name/, @message_channel_list)); # если указанного канала не существует в списке каналов то пропускаем
		my $kraken = $$channel_storage{$name};
             $kraken->read_data();
             $kraken->send_data();
	}
}

sub channel_goto { 
	my $command_message = shift;
	my $channel_storage = shift;
	chomp $command_message;
	$command_message =~ /^goto (\d+):(.*)/;
	my $message_number = $1;
     my $channels = $2;
        $channels =~ s/\s//g;
	my @message_channel_list = split(/,/,$channels);
	
	foreach my $name (keys %{$channel_storage}){
		next unless (grep (/$name/, @message_channel_list)); # если указанного канала не существует в списке каналов то пропускаем
		my $kraken = $$channel_storage{$name};
		   $kraken->goto_message($message_number);
	}
}

sub channel_skip { 
	my $command_message = shift;
	my $channel_storage = shift;
	chomp $command_message;
	$command_message =~ /^skip:(.*)/;
     my $channels = $1;
        $channels =~ s/\s//g;
	my @message_channel_list = split(/,/,$channels);
	
	foreach my $name (keys %{$channel_storage}){
		next unless (grep (/$name/, @message_channel_list)); # если указанного канала не существует в списке каналов то пропускаем
		my $kraken = $$channel_storage{$name};
		   $kraken->skip_message();
	}
}
sub channel_list { 
	my $channel_storage = shift;
     foreach my $name (keys %{$channel_storage}){
          my $message.="Channel:'$name' ";
          my $addr = $$channel_storage{$name}->var('address');
          $message .= "address:'$addr' " if defined $addr;
          my $port = $$channel_storage{$name}->var('port');
          $message .= "port:'$port' " if defined $port;
          my $protocol = $$channel_storage{$name}->var('protocol');
          $message .= "protocol:'$protocol' " if defined $protocol;
          print "$message\n";
    }
}

