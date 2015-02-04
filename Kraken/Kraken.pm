package Kraken;
use Data::Dumper;
my $ST_Kraken;
sub new{ 
    return $ST_Kraken if defined $ST_Kraken;
    $ST_Kraken  = bless {} ,shift;
    $ST_Kraken->_initialize_();
    $ST_Kraken;
}

sub _initialize_ {
        my $self=shift;
        $self->{io}      = ''; # Bit vector for select()
        $self->{queue}   = (); # queue of incoming data from channels () 
        $self->{sockets} = (); # @sockets[ fileno($socket) ] = $self->{channels}->{$channel}
        $self->{choose_channel}='';
        $self->{error}='';
        $self->{socket_to_delete} = ();
}

sub _get_self_ {
    my $class = shift;
    my $self =  ref $class ? $class : $class->new();
    $self;
}


sub choose_channel {
    my $self = _get_self_( shift );
    if (@_){
        $self->{choose_channel} = shift;
    }
    return $self->{choose_channel};
}

sub open_channel {
    my $self = _get_self_ (shift);
    my $name = $self->choose_channel();
    my $socket = Channel::open_channel($self->{channels}->{$name}, @_); 
    if (defined $socket){
        $self->add_io($socket) ; # second argument mean: this socket not for sendind, only for accept
        return 1;
    }
    my $err_text = Channel::_error($self->{channels}->{$name}) ;
    #print "Kraken::open_channel() $err_text\n";
    $self->error( $err_text );
    return undef;
}

sub add_io {
    my $self = _get_self_( shift );
    if (@_){
        my $socket = shift;
        vec ($self->{io} , fileno($socket) , 1) = 1; 
        
        my $name = $self->choose_channel();
        $self->{fileno_to_channel}[ fileno($socket) ] = $name;
        Channel::add_socket($self->{channels}->{$name}, $socket);
    }
    return $self->{io};
}

sub close_channel {
    my $self = _get_self_ (shift);
    my $name = $self->choose_channel();
    my @socks = $self->socket_list($name);
    foreach my $socket (@socks){
        $self->delete_io($socket);
    }
    return 1;
}

sub socket_list {
    my $self = _get_self_ (shift);
    my $name = shift;
    return  Channel::_get_socket_list($self->{channels}->{$name}, @_); 
}

sub error {
    my $self = _get_self_(shift);
    if (@_){
        $self->{error} = shift;
        return $self->{error};
    } else {
        my $error  = $self->{error};
        $self->{error} = undef; 
        return $error;
    }
}

sub delete_io {
    my $self = _get_self_( shift );
    if (@_){
        my $socket = shift;
        vec ($self->{io} , fileno($socket) , 1) = 0;
        my $name = $self->{fileno_to_channel}[ fileno($socket) ];
        delete  $self->{fileno_to_channel}[ fileno($socket) ];
        Channel::remove_socket($self->{channels}->{$name}, $socket);
    }
    return $self->{io};
}



sub channel_list {
    my $self = _get_self_( shift );
    my @keys = keys %{ $self->{channels} };
    return @keys ;
}


sub add_channel {
    #print "Kraken: sub add_channel\n";
    my $self = _get_self_( shift );
    my $name = shift;
    
    if (not exists $self->{channels}->{$name}){
        #print "Create channel '$name'\n";
        $self->{channels}->{$name} = Channel->new($name) ;
        $self->choose_channel( $name );
        return 1;
    }
    return undef;
}

sub delete_channel {
    my $self = _get_self_( shift );
    my $name = shift;
    $self->close_channel();
    delete $self->{channels}->{$name};
    return 1
}

sub queue {
    my $self  = _get_self_( shift ) ;  
    if (@_){
        my $index   = shift;
        my $data    = shift;
        #print "push $index $data\n";
        push @{ $self->{queue} }, $index;
        push @{ $self->{queue} }, $data;
        return 1;
    }
    # without arguments
    my $index   =  shift @{ $self->{queue} } || return undef;
    my $data    =  shift @{ $self->{queue} } || return undef;
    #print "shift $index $data\n";
    return wantarray ? ($index, $data) : undef;    
}

sub queue_index {
    my $self  = _get_self_( shift ) ;  
    my @queue = @{ $self->{queue} };
    my %uniq;
    
    for ( my $i=0 ; $i<$#queue+1 ; $i+=2){
        my $key = $queue[$i];
        my $value = $queue[$i+1];
        $uniq{$key}=1;
    }
    my @keys = keys %uniq;
    
    unless (@keys){
        #print "NOOOOOOOOOOOOOOO!1!!!!\n";
        return undef;
    }

    #print "uniq queue_indexes: \n";
    #print Dumper(@keys);
    
    #print "ZZZZZZZZZ\n";
    return @keys ;
}

# Creating accessors. See http://perldesignpatterns.com/?AccessorPattern

sub get_socket {
    my $self  = _get_self_(shift);
    my $index = shift;
    my $name  = $self->{fileno_to_channel}[ $index ] ;
    #$self->choose_channel($name);
    #print "Kraken::get_socket() $index $name\n";
    return Channel::get_socket($self->{channels}->{$name}, $index);
};

sub get_channel_name {
    my $self  = _get_self_(shift);
    my $index = shift;
    
#    my $i=0;
#    foreach my $channel ( @{ $self->{fileno_to_channel} } ){
#        $channel = "undef" unless $channel;
#        print "get_channel_name() $i = $channel\n";
#        $i++;
#    }
    return exists $self->{fileno_to_channel}[ $index ] ? $self->{fileno_to_channel}[ $index ] : undef ;
};

sub get_indexes_by_channel {
    my $self  = _get_self_(shift);
    my $arg_channel = shift;
    
    my @return;
    my @array = @{ $self->{fileno_to_channel} };
    my $index = -1;
    foreach my $channel ( @array){
        $index++;
        next unless defined $channel;
        #print "channel $channel $index\n";
        if ("$channel" eq "$arg_channel"){
            push @return, $index;
        }
    }
    return @return;
};

foreach my $field ( qw(file_mode file_path file_handler position file_list choose_file file_name get_data amount file_goto file_eof) ){
    *{"$field"} = sub {
        my $self = _get_self_(shift);
        my $name = $self->choose_channel();
        #print Dumper($self->{channels}->{$name}->{sources});
        Source::accessor($self->{channels}->{$name}->{sources}, $field, @_);
    }
}

foreach my $field ( qw(var) ){
    *{"$field"} = sub {
        my $self = _get_self_(shift);
        my $name = $self->choose_channel;
        Config::var($self->{channels}->{$name}->{config}, @_);
    }
}

sub dead_socket {
    my $self = _get_self_(shift);
    if (@_){
        my $index = shift;
        my $value = shift;
        $self->{dead}->{$index}=1;
        if (defined $value and $value == 0){
            $self->{dead}->{$index}=0;
        }
    }
    my @dead = grep { $self->{dead}->{$_} == 1 } keys %{ $self->{dead} };
    return @dead;
}

sub stop_loop {
    my $self  = _get_self_( shift ) ;
    $self->{loop} = 0;
}

sub start_loop {
    use List::MoreUtils qw(true indexes);
    
    my $self  = _get_self_( shift ) ;
       $self->{loop} = 1;
    while ($self->{loop}){
        if ( select (my $rout=$self->{io}, undef, undef, 0) ){
            my @indexes = ( indexes { $_== 1 } ( split //, unpack("b*", $rout) ) ); # преобразует бит вектор в массив индексов
            foreach my $index ( @indexes ) {
               my $socket   = $self->get_socket($index);
               my $channel = $self->get_channel_name($index); 
               $self->choose_channel($channel);
               my $recv_ret = $socket->recv(my $buffer, 1024);
               
               if (not defined $recv_ret){
                    my $incoming = $socket->accept();
                    my $host     = $incoming->peerhost();
                    my $port     = $incoming->peerport();
                       $self->add_io($incoming);
                    #print "Accept $channel $host:$port\n";
                    next;
               }
               
               my $host     = $socket->peerhost();
               my $port     = $socket->peerport();
               if ($buffer eq '' ){ # read from closed socket
                    $self->dead_socket($index);
                    $self->run_queue();
                    next;
                }
                my $chomp_buf = $buffer;
                   $chomp_buf =~ s/\r|\n//g;
                print "recv: $index $channel $host:$port $chomp_buf\n";
                $self->queue($index, $buffer);
            }
        } else {
            $self->run_queue();
        }
    }
}


sub run_queue {
    my $self = _get_self_(shift);
    my ($index,  $data) = $self->queue();
    return undef if not defined $index;
    return undef if not defined $data;
    #print "Index: $index  Data: $data\n";
      
    my $channel = $self->get_channel_name($index); 
    #print "process_command() '$channel'\n";
    
    if ($channel eq 'command'){
        #print "run_callback()\n";
        Interface->run_callback($index, $data); 
    } else { 
        my $response = Channel::process_incoming_data($self->{channels}->{$channel}, $data);
        $self->send_client($index, $response) if $response;
    }
    
    my @dead = $self->dead_socket();
    my @queue_indexes = $self->queue_index();
    foreach my $dead_index (@dead){
        my $index_is_present=0;
        if (@queue_indexes){
            foreach my $q_index (@queue_indexes){
                if ($dead_index == $q_index){
                    #print "$dead_index == $q_index\n";
                    $index_is_present=1;
                }
            }
        }
        if ($index_is_present == 0){
            my $socket = $self->get_socket($dead_index);
            $self->delete_io($socket);
            $self->dead_socket($dead_index, 0);
        }
    }
    return 1;
}

sub send_client {
    my $self    = _get_self_(shift);
    my $index   = shift;
    my $data    = shift;
    my $socket  = $self->get_socket($index);
    my $channel = $self->get_channel_name($index);
    
    return undef if not defined $data;
    return 2 unless $socket->peerhost();
    

    my $channel  = $self->get_channel_name($index); 
    my $host     = $socket->peerhost();
    my $port     = $socket->peerport();

    my $chomp_data = $data;
    $chomp_data =~ s/\r|\n//g;
    print "send: $channel $host:$port $chomp_data\n";
    my $send_data = Channel::process_outgoing_data($self->{channels}->{$channel}, $data);
    eval { $socket->send($send_data) };
    
    if ($@){
        print $@."\n";
        return undef;
    }
    
    return 1;
}

1;

