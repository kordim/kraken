# Author: D. Korytsev (dkorytsev at gmail dot com)
# Aim: 
# $Id$

package Source;
use strict;
use Data::Dumper;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval nanosleep clock_gettime clock_getres clock_nanosleep clock stat );

sub new {
    my $self = bless {}, shift;
    $self;
}

sub accessor {
    my $self = shift;
    my $field = shift;
    #print "Source::accessor $field @_\n";
    $self->$field(@_);
}

sub choose_file {
    my $self = shift;
    if (@_){
        $self->{selected_file}=shift;
    }
    #print "choosed file $self->{selected_file}\n";
    return $self->{selected_file};
}

sub file_list {
    my $self = shift;
    return keys %{ $self->{files} };
}

sub position { 
    my $self = shift;
    my $file = $self->choose_file();
    
    if (not exists $self->{files}->{$file}->{position} ){
        $self->{files}->{$file}->{position}=0
    }

    if (@_){
        my $pos = shift;
        if ($pos eq '++'){
            $pos = $self->{files}->{$file}->{position} + 1;
            }
        $self->{files}->{$file}->{position} = $pos;
    }
    return $self->{files}->{$file}->{position};
}

sub file_goto {
    my $self     = shift;
    return undef unless @_;
    my $position = shift;
    my $handler = $self->file_handler();
    
    my $curpos= tell $handler;
    #print "Source::file_goto(): file postition Before seek $curpos\n";

    $self->position(0);
    seek ($handler , 0 , 0);
    
    $curpos= tell $handler;
    #print "Source::file_goto(): file postition After seek $curpos\n";
    
    for ( my $i=0 ; $i<$position ; $i++){
        
        #print "Source::file_goto() shift to postion $position \n";
        my $data = $self->get_data();
        #print "goto: $data\n";
        }
    return 1;
}

sub file_handler {
    my $self = shift;
    my $file = $self->choose_file();
    if (@_){
        my $handler = shift;
        #print "Source::file_handler() set handler: $handler\n";
        $self->{files}->{$file}->{filehandler} = $handler;
    }
    my $handler = $self->{files}->{$file}->{filehandler};
    #print "Source::file_handler() get handler: $handler\n";
    return $handler;
}


sub file_name {
    my $self = shift;
    my $file = $self->choose_file();
    if (@_){
        $self->{files}->{$file}->{filename}=shift;
        #$self->file_mode('plain');
        }
    return $self->{files}->{$file}->{filename};
}

sub amount {
    my $self = shift;
    my $file = $self->choose_file();
    
    if ( not exists $self->{files}->{$file}->{amount} ){
        #print "create message amount counter\n";
        $self->{files}->{$file}->{amount} = 0;
    }
    
    if (@_){
        my $action = shift;
        $self->{files}->{$file}->{amount}++ if $action eq "++";
        $self->{files}->{$file}->{amount}-- if $action eq "--";
        $self->{files}->{$file}->{amount}=$action if $action =~ /^\d+$/;
        }
    return $self->{files}->{$file}->{amount} ;
}

sub file_eof {
    my $self = shift;
    my $file = $self->choose_file();
    
    if (@_){
        $self->{files}->{$file}->{'eof'}=shift;
    }
    return $self->{files}->{$file}->{'eof'} || 0;
}

sub readbuf {
    my $self = shift;
    my $file = $self->choose_file();
    
    if (@_){
        $self->{files}->{$file}->{'readbuf'}=shift;
        return 1;
    }
    my $buf = $self->{files}->{$file}->{'readbuf'};
    $self->{files}->{$file}->{'readbuf'} = '';
    return $buf;
}

sub file_mode {
    my $self = shift;
    my $file = $self->choose_file();
    #print "file_mode() choosed " . $file  . "\n";
    if (@_){
        my $mode = shift; # plain or packet
        return undef unless  grep { $mode eq $_} qw(packet plain);
        $self->{files}->{$file}->{mode}=$mode;
        #$self->file_close();
        #return 0 unless $self->file_open();
        
    }
    return $self->{files}->{$file}->{mode};
}

sub file_open {
    my $self = shift;
    my $file = $self->choose_file();
    my $file_path = $self->{files}->{$file}->{filename};
    open my $handler , "<$file_path" || do { $self->{'error'}=$! ; return 0};

    $self->file_handler($handler);
    
    my $seconds = time(); 
    #print "$seconds start count messages...\n";
  
    $self->amount(0);
    while (1){
        last unless $self->get_data() ;
        $self->amount('++');
    }
    $self->file_eof(0);
    $self->file_goto(0);
    
    $seconds = time(); 
    #print "$seconds finished count messages...\n";
    
    return 1;
}



sub file_close {
    my $self = shift;
    my $file = $self->choose_file();
    eval { close $self->file_handler() };
    return 1;
}

sub get_data {
    my $self = shift;
    my $file = $self->choose_file();
    if  ( $self->file_eof() ){
         warn "eof before get_data\n";
         return 0 
    }
    
       return $self->read_plain() if $self->file_mode() eq 'plain';
       return $self->read_packet() if $self->file_mode() eq 'packet';
    
}


sub read_plain{
        my $self= shift;
        my $FH = $self->file_handler();
        my $data = readline($FH);
        
        if  (not defined $data){
               $self->file_eof(1);
               $self->readbuf(); # clear read buffer
               return 0;
        }
        
        $self->position('++');
        $self->readbuf($data); 
        return 1;
}



sub read_packet{
        my $self = shift;
        my $readed  = read $self->file_handler() , my $size , 4;
           $readed  = read $self->file_handler() , my $timestamp , 8;
        
        if ($readed == 0){
               $self->file_eof(1);
               $self->readbuf(); # clear read buffer
               return 0;
        }

        my $hr_size = unpack("N",$size);
           $readed = read ( $self->file_handler() , my $data , $hr_size );
        
        if ($readed == 0){
               $self->file_eof(1);
               $self->readbuf(); # clear read buffer
               return 0
        }
        
        $self->position('++');
        $self->readbuf($data);
        return 1;
}

1;



__END__



























