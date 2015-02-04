package Channel;
#our @ISA = qw(Config);
use Config;
use Data::Dumper;
use Socket;
use IO::Socket;
use IO::Socket::Multicast;
use Socket qw/SOL_SOCKET SO_RCVBUF IPPROTO_TCP TCP_NODELAY/;                                        
use IPC::Open2;

sub new{ 
    my $self =  bless {} ,shift;
    $self->_initialize_();
    $self;
}

sub _initialize_ {
        my $self=shift;
        $self->{config}  = Config->new();
        $self->{sources} = Source->new();
        $self->{error}="";
    }

sub add_socket {
    my $self       = shift;
    my $socket     = shift;
    my $fileno = fileno( $socket );
    $self->{sockets}->{$fileno}=$socket;
}


sub remove_socket {
    my $self   = shift;
    my $socket = shift;
    my $fileno = fileno $socket;
    close  $self->{sockets}->{$fileno}; 
    delete $self->{sockets}->{$fileno};
    return 1;
}

sub get_socket {
    my $self   = shift;
    my $fileno = shift;
    if (exists $self->{sockets}->{$fileno}){
        #print "Channel::get_socket for index $fileno\n";
        return $self->{sockets}->{$fileno};
    }
    return undef;
}

sub get_address {
    my $self   = shift;
    if (@_){
        #print "Sub get_address: \n";
        my $socket = shift;
        #print "Socket: $socket\n";
        my $host = $socket->sockhost();
        my $port = $socket->sockport();
        #print "Peer address:  $host:$port\n ";
        return $addr;
    }
    return undef;
}


sub _get_socket_list {
    my $self       = shift;
    return  %{ $self->{sockets} };
}


sub _get_conf {
    my $self = shift;
    my $name = shift;
    my $value = Config::var($self->{config}, $name);
    unless ($value) {
        $self->_error("ERROR: Channel::_get_conf '$name' not exists\n");
        return undef;
    }
    return $value;
}

sub _set_conf {
    my $self  = shift;
    my $name  = shift;
    my $value = shift;
    Config::var($self->{config}, $name, $value);
    1;
}

sub _error {
    my $self = shift;
    if (@_){
        $self->{error} .= shift;
        return $self->{error};
        } 
    
    if (defined $self->{error} ){
        my $error = $self->{error};
        $self->{error}=undef; # очистка после чтения
        return $error;
        }
}
####################
# Нужно сделать запуск препроцессора один раз при добавлении его в конфиг
# И получение данных из него "онлайн" а не форкая каждый раз новый процесс
#sub add_processor {
#    my $self = shift;
#    my $path = $self->_get_conf('incoming_processor') || return undef;
#    $self->{proc_pid} = open2($self->{in_proc_fd}, $self->{out_proc_fd}, $self->{exec_proc_df}, $path ) || return undef; 
#    return 1;
#}
#
#sub process_incoming_data {
#    my $self = shift; 
#    my $data = shift; 
#    my $in   = $self->{in_proc_fd};
#    my $out  = $self->{out_proc_fd};
#    print $in $data;
#    my $result;
#    while( sysread $exec_out, my $buffer, 64 ){
#        $result .= $buffer ;
#    } 
#
#}
#
# А пока полюзуемся старой схемой
#
####################################################################
sub process_incoming_data {
   my $self = shift; 
   my $data = shift; 
   my $path = $self->_get_conf('incoming_processor');
   return undef unless $path;
   
   my $pid = open2(my $exec_out, my $exec_in, $path ) || return undef; 
   print $exec_in $data;
   close $exec_in;
                  
   my $result;
   while( sysread $exec_out, my $buffer, 64 ){ $result .= $buffer ;}; 
   close $exec_out;
   waitpid($pid, 0); 
   return $result;
}

sub process_outgoing_data {
   my $self = shift; 
   my $data = shift; 
   my $path = $self->_get_conf('outgoing_processor') || return $data;
   
   my $pid = open2(my $exec_out, my $exec_in, $path ) || return $data; 
   print $exec_in $data;
   close $exec_in;
                  
   my $result;
   while( sysread $exec_out, my $buffer, 64 ){ $result .= $buffer ;}; 
   close $exec_out;
   waitpid($pid, 0); 
   return $result;
}

sub open_channel {
    my $self = shift;
    my $address  = $self->_get_conf('address')  || return undef;
    my $port     = $self->_get_conf('port')     || return undef;
    my $protocol = $self->_get_conf('protocol') || return undef;
    
    #print "Channel:open_channel: -> $address:$port @ $protocol\n";
    my $socket;
    if ($protocol eq 'tcp'){
        $socket = IO::Socket::INET->new( LocalAddr => $address, LocalPort => $port, Proto => 'tcp', ReuseAddr=>1 , Listen=>SOMAXCONN) or $self->_error("$@\n");
    }
    if ($protocol eq 'tcp_client'){
        $socket = IO::Socket::INET->new( PeerHost=>$address, PeerPort => $port, Proto => 'tcp') or $self->_error("$@\n");
    }
    elsif ($protocol eq 'multicast'){
	    $socket  = IO::Socket::Multicast->new( ReuseAddr=>1, PeerHost=>$address, PeerPort=>$port) or $self->_error(@_);
	    $socket->mcast_dest("$address:$port");
      my $listener = IO::Socket::Multicast->new( ReuseAddr=>1, LocalPort=>$port) or $self->_error(@_);
	    $listener->mcast_add($address);
     } 
    elsif ($protocol eq 'multicast_client'){
      $socket = IO::Socket::Multicast->new( ReuseAddr=>1, LocalPort=>$port) or $self->_error(@_);
	 $socket->mcast_add($address);
     } 
    elsif ($protocol eq 'udp_client'){
      $socket = IO::Socket::INET->new(PeerHost=>$address, PeerPort => $port, Proto => 'udp') or $self->_error(@_);
     } 
    elsif ($protocol eq 'udp'){
      $socket = IO::Socket::INET->new(LocalAddr=>$address, LocalPort => $port, Proto => 'udp') or $self->_error(@_);
     } 
    $self->add_socket($socket) if defined $socket;
    return $socket || undef;
}

sub close_channel {
    my $self = shift;
    for my $socket ( values %{ $self->{sockets} }){ 
        close $socket
    }
    
}

sub wrapper {
    my $self   = shift;
    my $method = shift;
    return $self->$method(@_);
}
1;
