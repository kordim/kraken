# Author: D. Korytsev (dkorytsev at gmail dot com)
# Aim: 
# $Id$

package Source;
use strict;
use Data::Dumper;

sub new {
    my $self = bless {}, shift;
    $self;
}

sub accessor {
    my $self = shift;
    my $field = shift;
    $self->$field(@_);
}

sub choose_file {
    my $self = shift;
    if (@_){
        $self->{selected_file}=shift;
    }
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
    
    $self->position(0);
    
    seek $self->file_handler() , 0 , 0;
    
    for ( my $i=0 ; $i<$position ; $i++){
        $self->get_data()
        }
    return 1;
}

sub file_handler {
    my $self = shift;
    my $file = $self->choose_file();
    if (@_){
        $self->{files}->{$file}->{filehandler}=shift;
    }
    return $self->{files}->{$file}->{filehandler};
}


sub file_name {
    my $self = shift;
    my $file = $self->choose_file();
    if (@_){
        $self->{files}->{$file}->{filename}=shift;
        $self->file_mode('plain');
        }
    return $self->{files}->{$file}->{filename};
}

sub amount {
    my $self = shift;
    my $file = $self->choose_file();
    
    if ( not exists $self->{files}->{$file}->{amount} ){
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
        $self->{files}->{$file}->{eof}=shift;
    }
    return $self->{files}->{$file}->{eof} || 0;
}

sub file_mode {
    my $self = shift;
    my $file = $self->choose_file();
    #print "file_mode() choosed " . $file  . "\n";
    if (@_){
        my $mode = shift; # plain or packet
        return undef unless  grep { $mode eq $_} qw(packet plain);
        $self->{files}->{$file}->{mode}=$mode;
        $self->file_close();
        $self->file_open();
    }
    return $self->{files}->{$file}->{mode};
}

sub file_open {
    my $self = shift;
    my $file = $self->choose_file();
    open my $handler , "<$self->{files}->{$file}->{filename}" || return 0;
    $self->file_handler($handler);
    
    $self->amount(0);
    while (1){
        $self->get_data() ? $self->amount('++') : last;
        }
    $self->file_eof(0);
    $self->file_goto(0);
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
         return undef 
    }
    
    my $data;
    $data = readline $self->file_handler()              if ($self->file_mode() eq 'plain');
    $data = $self->read_packet($self->file_handler() )  if ($self->file_mode() eq 'packet');
    
    $self->position('++');
    
    if ( eof $self->file_handler()  ){
        $self->file_eof(1); 
        $self->file_goto(0); 
    }
    return $data ;
}

sub read_packet{
        my $self = shift;
        read $self->file_handler() , my $size , 4;
        read $self->file_handler() , my $timestamp , 8;
        $size = unpack("l",$size);
        read ( $self->file_handler() , my $data , $size );
        return $data || undef;
}

1;



__END__



























