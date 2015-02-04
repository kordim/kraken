package Interface;
use Data::Dumper;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval nanosleep clock_gettime clock_getres clock_nanosleep clock stat );

my $HelpMsg;
while (<DATA>){
$HelpMsg.=$_;
}

my $ST_Interface;
sub new{ 
    return $ST_Interface if defined $ST_Interface;
    $ST_Interface  = bless {} ,shift;
    $ST_Interface->_initialize_();
    $ST_Interface;
}

sub _initialize_ {
        my $self=shift;
        $self->{cb_list} = ();
        $self->{error}='';
}

sub _get_self_ {
    my $class = shift;
    my $self =  ref $class ? $class : $class->new();
    $self;
}

sub callback {
    my $self = _get_self_(shift);
    if (@_){   # run callback 
        my $callback = shift;
        push @{ $self->{cb_list} } , $callback ;
        return 1;
    }
    return $self->{cb_list};
}

sub cb_list {
    my $self = _get_self_(shift);
    return @{ $self->{cb_list} };
}

sub run_callback {
    my $self = _get_self_(shift);
    for my $cb ( $self->cb_list() ){
        last if $self->$cb(@_);
    }
    return 0
}

Interface->callback("help");
Interface->callback(add_channel);
Interface->callback(config_channel);
Interface->callback(open_channel);
Interface->callback(close_channel);
Interface->callback(delete_channel);
Interface->callback(list_channel);
Interface->callback(list_clients);
Interface->callback(add_file);
Interface->callback(select_file);
Interface->callback(read_mode);
Interface->callback(file_list);
Interface->callback(set_position);
Interface->callback(get_position);
Interface->callback(send_data);
Interface->callback(send_to_channel);

sub help {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^help$/){
        return Kraken->send_client($index,"$HelpMsg\n");
    }
    return 0
}

sub add_channel {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^add_channel\s+(.+?)$/){
        my $channel = $1;
 #       print "sub: Interface add_channel ===> '$channel'\n";
        
        my $result =  Kraken->add_channel($channel) ? "add_channel: $channel OK\n" : "add_channel: $channel Already exists \n";
        Kraken->send_client($index, $result);

        
        return 1
    }
    return 0
}

sub delete_channel {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^delete_channel\s+(.+?)$/){
        my $channel = $1;
#        print "INFO: Interface::delete_channel() '$channel'\n";
        
        my $result = Kraken->delete_channel($channel) ? "delete_channel: OK\n" : "delete_channel: $channel not exists\n ";
        Kraken->send_client($index, $result);
        
        return 1
    }
    return 0
}

sub config_channel {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^config_channel\s+(\S+?)\s+(\S+?)=(\S+?)$/){
        my $channel = $1;
        my $name    = $2;
        my $value   = $3;
#        print "INFO: Interface::config_channel() '$channel' :: '$name'='$value'\n";

                     Kraken->choose_channel($channel);
                     
        
        my $result;
        if ( Kraken->var($name, $value) ){
            $result = "config_channel: '$channel' '$name' = '$value' OK\n";
#            if ($name eq "incoming_processor") {
#            }
        
        }else{
            $result = "config_channel: '$channel' '$name' = '$value'  ERROR (channel not exists)\n";
        }
        
        Kraken->send_client($index, $result);
        return 1
    }
    return 0
}

sub add_file {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^add_file\s+(\S+?)\s+(\S+?)=(\S+?)$/){
        my $channel = $1;
        my $alias   = $2;
        my $path    = $3;
        Kraken->choose_channel($channel);
        Kraken->choose_file($alias) ;
        Kraken->file_name($path);
        return 1
    }
    return undef
}

sub select_file {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^select_file\s+(\S+?)\s+(\S+?)$/){
        my $channel = $1;
        my $alias   = $2;
        Kraken->choose_channel($channel);
        Kraken->choose_file($alias) ;
        my $selected = Kraken->choose_file();
        Kraken->send_client($index, "file: $selected selected\n");
        return 1
    }
    return undef
}

sub read_mode {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^read_mode\s+(\S+?)\s+(\S+?)=(\S+?)$/){ # mode 
        my $channel = $1;
        my $alias   = $2;
        my $mode    = $3;
        Kraken->choose_channel($channel);
        Kraken->choose_file($alias) ;
        Kraken->file_mode($mode);
        return 1
    }
    return 0
}
sub file_list {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^file_list\s+(\S+?)$/){ # mode 
        my $channel = $1;
        Kraken->choose_channel($channel);
        foreach my $alias (Kraken->file_list()){
            Kraken->choose_file($alias);
            my $name = Kraken->file_name();
            my $pos  = Kraken->position();
            Kraken->send_client($index, "file: $alias $name $pos\n");
        }
        return 1
    }
    return 0
}

sub set_position {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^set_position\s+(\S+?)\s+(\S+)\s+(\S+)$/){ # mode 
        my $channel  = $1;
        my $alias    = $2;
        my $position = $3;
        Kraken->choose_channel($channel);
        Kraken->choose_file($alias);
        Kraken->file_goto($position);
        Kraken->send_client($index, "file: Position is set to $position\n");
        return 1
    }
    return 0
}

sub get_position {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^set_position\s+(\S+?)\s+(\S+)$/){ # mode 
        my $channel  = $1;
        my $alias    = $2;
        Kraken->choose_channel($channel);
        Kraken->choose_file($alias);
        my $position = Kraken->position();
        Kraken->send_client($index, "Position is $position\n");
        return 1
    }
    return 0
}


sub open_channel {
    my $self = shift;
    my $index = shift;
    my $args = join " ", @_;
    if ($args =~ /^open_channel\s+(\S+?)$/){
        my $channel = $1;
#        print "INFO: Interface::open_channel() '$channel'\n";

                     Kraken->choose_channel($channel);
        my $result = Kraken->open_channel() ? "open_channel: OK\n" : "open_channel ". Kraken->error() ."\n";
        Kraken->send_client($index, $result);
        return 1
    }
    return undef
}

sub close_channel {
    my $self = shift;
    my $index = shift;
    my $args = join " ", @_;
    if ($args =~ /^close_channel\s+(\S+?)$/){
        my $channel = $1;
#        print "INFO: Interface::close_channel() '$channel'\n";
        
        if ($channel eq 'command'){
            return Kraken->send_client($index, "ERROR: close_channel() 'command' cannot be closed. Use shutdown instead\n");
        }
            
                     Kraken->choose_channel($channel);
        my $result = Kraken->close_channel() ? "close_channel: OK\n" : "close_channel: ERROR\n";
                     Kraken->send_client($index, $result);

        return 1
    }
    return 0
}

sub start_autosend { 
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^autosend\s+(\S+)$/){
        my $channel = $1;   
        Kraken->choose_channel($channel);
        my $rate = Kraken->rate();
        my $wait = Kraken->waitclient() || 0;
        my $repeat = Kraken->repeat()   || 1
    }
}


sub send_data { 
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    return undef unless ($args =~ /^send\s+(\S+)\s+(\S+)/);
    
    my $channel = $1;   
    my $count   = $2 || 1;
        
    if ( $channel eq 'command'){
        Kraken->send_client($index, "ERROR: send() is not available for 'command' channel\n");
        return undef;
        }
    
    Kraken->choose_channel($channel);
    if ( $count eq "*" ){
         $count = Kraken->amount();
         my $repeat = Kraken->var('repeat') || 1;
         $count*=$repeat; 
    }
        
    for (my $i = 0 ; $i < $count ; $i++){
            Kraken->queue($index, "send_to_channel $channel");
    }
    return 1;
}

sub send_to_channel {
    my $self  = shift;
    my $index = shift; # от кого пришла команда и кому слать ответ
    my $args  = join " ", @_;
    return undef unless ( $args =~ /^send_to_channel\s+(\S+)/ );
    my $channel = $1;
    
    # Сравниваем текущее время с временем хранящемся в 'ignore_until'
    # если еще рано то добавляемся в конец очереди 
    
    Kraken->choose_channel($channel);
    if (my $ignore_until = Kraken->var('ignore_until')){
        my ($seconds, $microseconds) = gettimeofday; 
        $seconds.=$microseconds;
        #print "Ignore until $seconds $ignore_until\n";
        if ($seconds < $ignore_until){
            Kraken->queue($index, "$args");
            return 1;
            }
        Kraken->var('ignore_until',0);
        }
     
     my $data = Kraken->get_data(); 
     
     # Если дошли до конца файла и требуется поатор то перематывает на начало
     unless (defined $data){
        Kraken->send_client($index, "EOF reached.\n");
        Kraken->file_goto(0);
        Kraken->file_eof(0);
        Kraken->queue($index, "$args");
        return undef;
     }
     
     foreach my $idx (Kraken->get_indexes_by_channel($channel)){
        #print "send to client $idx $data\n";
        my $code = Kraken->send_client($idx, $data); 
        if ($code == 1){
            Kraken->send_client($index, "send: OK: \n");
            }
        elsif (! defined $code){
            Kraken->send_client($index, "send: ERROR \n" );
            }
        }
        
        # Смотрим на 'rate' вычисляем время после которого можно постить
        if (my $rate = Kraken->var('rate') ){
            #print "Rate = $rate\n";
            my ($seconds, $microseconds) = gettimeofday; 
            $seconds.=$microseconds;
            $seconds+=int(10**6/$rate);
            #print "set ignore_until=$seconds\n";
            Kraken->var('ignore_until',$seconds);
        }
return 1;
}

sub list_channel {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^list_channel$/){
        
        Kraken->send_client($index, "List of channels: \n");
        foreach my $ch  ( Kraken->channel_list() ){
            Kraken->send_client($index, "channel: '$ch'\n");
        }
        return 1
    }
    return 0
}

sub list_clients {
    my $self  = shift;
    my $index = shift;
    my $args  = join " ", @_;
    if ($args =~ /^list_client\s+(\S+?)$/){
        my $channel = $1;
        Kraken->send_client($index, "List of connected clients:\n");
        my %sockets = Kraken->socket_list($channel);
        foreach my $idx (keys %sockets){
            my $addr = $sockets{$idx}->peerhost();
            my $port = $sockets{$idx}->peerport();
            next unless $addr;
            Kraken->send_client($index, "id: $idx  $addr:$port\n");
            }
        return 1
        }
    return 0
}


1;
__DATA__

Channel commands:

add_channel <channel name> Add channel. Need to be run before channel configuration. 
config_channel <channel name> <variable name>=<value> Set channel configuration
open_channel <channel_name>   Open channel connection
close_channel <channel_name>  Close all channel connections
delete_channel <channel_name> Close channel and remove from configuration
list_channel Return list of channels
list_clients <channel name> Return list of clients connected to channel. Format: <client id> <address>:<port>
list_file <channel_name> Return list of opened files. 


Sending commands:

send <channel name> <count>|<*> : Send defined number of messages to all clients connected to channel. Or all messages till end of file
set_position <channel name> <source name> <position> : Go to defined position in source file. <position> is a line number or packet number
get_position <channel name> <source name> <position> : Return current line number in opened file


Configuration commands:
config_channel <channel_name> <variable name>=<value>
    where <variable name>:
    
    address            : Ip address
    port               : Port
    protocol           : tcp, tcp_client, udp, udp_client, multicast, multicast_client
    incoming_processor : Path to program for processing incoming messages
    outgoing_processor : Path to program for processing outgoing messages
                         Processors must read data from stdin and print processed data to stdout
    repeat             : repeat number. Useful for "send <channel> *";
    rate               : Msg per seconds. Sending rate

add_file <channel_name> <source name>=<file_path> : add messages source file. One channel can work with several files. 
select_file <channel_name> <source name>          : select active file 
read_mode <channel name> <source name>=<mode>     : Set file read mode 'plain' or 'packet'

#############################
Example of configuration
#!/bin/sh
dest="172.26.2.124 22222"
Kraken.pl $dest
echo "add_channel    channel_1"                                                 | nc $dest 
echo "config_channel channel_1 protocol=tcp"                                    | nc $dest
echo "config_channel channel_1 address=172.26.2.124"                            | nc $dest
echo "config_channel channel_1 port=33633"                                      | nc $dest
echo "config_channel channel_1 incoming_processor=/home/dmitryko/in_prep.pl"    | nc $dest
echo "config_channel channel_1 outgoing_processor=/home/dmitryko/out_prep.pl"   | nc $dest
echo "config_channel channel_1 repeat=5"                                        | nc $dest
echo "config_channel channel_1 rate=50"                                         | nc $dest
echo "add_file       channel_1 file_1=/home/dmitryko/qqq.txt"                   | nc $dest
echo "read_mode      channel_1 file_1=plain"                                    | nc $dest
echo "open_channel   channel_1"                                                 | nc $dest


