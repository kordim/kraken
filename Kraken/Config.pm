# Author: D. Korytsev (dkorytsev at gmail dot com)
# Aim: 
# $Id$

package Config;
use strict;

# Тут всё просто: храним настройка канала порт, адрес, режим и прочее
sub new {
    my $self = bless {}, shift;
    $self->_initialize_();
    $self;
}

sub _initialize_ {
    my $self = shift;
}

sub var {
    my $self = shift;
    my $name = shift;
    if (@_){
        $self->{$name} = shift;
        return 1;
    }
   return $self->{$name} || undef;
}

#sub var {
#    my $self = shift;
#    my $name = shift;
#    if (@_){
#        my $value = shift;
#        if ($value ne ''){
#          $self->{$name} = $value;
#        }elsif(exists $self->{$name}){
#             delete $self->{$name};
#        }
#        return 1;
#        #print "var set: $name = $self->{$name}\n";
#    }
#   return $self->{$name} || undef;
#  #print "var get: $name = $self->{$name}\n";
#}



1;



__END__

