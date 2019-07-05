# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright 2017, 2018 The Sympa Community. See the AUTHORS.md file at the
# top-level directory of this distribution and at
# <https://github.com/sympa-community/sympa.git>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Sympa::Request::Handler::apply_template_to_list;

use strict;
use warnings;
use Encode qw();
use English qw(-no_match_vars);

use Sympa;
use Sympa::Aliases;
use Conf;
use Sympa::List;
use Sympa::LockedFile;
use Sympa::Log;
use Sympa::Template;

use base qw(Sympa::Request::Handler);

my $log = Sympa::Log->instance;

use constant _action_regexp   => qr{reject|listmaster|do_it}i;
use constant _action_scenario => 'apply_template_to_list';

sub _twist {
    my $self    = shift;
    my $request = shift;

    my $robot_id = $request->{context};
    my $listname = lc($request->{listname} || '');
    my $param    = $request->{parameters};
    my $pending  = $request->{pending};
    my $notify   = $request->{notify};
    my $sender   = $request->{sender};

    # Obligatory parameters.
    foreach my $arg (qw(template)) {
        unless (defined $param->{$arg} and $param->{$arg} =~ /\S/) {
            $self->add_stash($request, 'user', 'missing_arg',
                {argument => $arg});
            $log->syslog('err', 'Missing list parameter "%s"', $arg);
            return undef;
        }
    }

    ## Check the template supposed to be used exist.
    my $template_file =
        Sympa::search_fullpath($robot_id, 'config.tt2',
        subdir => 'create_list_templates/' . $param->{template});
    unless (defined $template_file) {
        $log->syslog('err', 'No template %s found', $param->{template});
        $self->add_stash($request, 'user', 'unknown_template',
            {tpl => $param->{template}});
        return undef;
    }

    # Create list object.
    my $list;
    unless ($list =
        Sympa::List->new($listname, $robot_id, {skip_sync_admin => 1})) {
        $log->syslog('err', 'Unable to open list %s', $listname);
        $self->add_stash($request, 'intern');
        return undef;
    }
    my $list_param = {
        subject        => $list->{'admin'}{'subject'},
        status         => $list->{'admin'}{'status'},
        topics         => $list->{'admin'}{'topics'},
        listname       => $listname,
        owner          => $list->{'admin'}{'owner'},
        editor         => $list->{'admin'}{'editor'},
        creation       => $list->{'admin'}{'creation'},
        creation_email => $list->{'admin'}{'creation_email'},
    };

    # Lock config before opening the config file.
    my $lock_fh = Sympa::LockedFile->new($list_dir . '/config', 5, '>');
    unless ($lock_fh) {
        $log->syslog('err', 'Impossible to create %s/config: %m', $list_dir);
        $self->add_stash($request, 'intern');
        return undef;
    }

    my $config = '';
    my $template =
        Sympa::Template->new($robot_id,
        subdir => 'create_list_templates/' . $param->{'template'});
    unless ($template->parse($list_param, 'config.tt2', \$config)) {
        $log->syslog('err', 'Can\'t parse %s/config.tt2: %s',
            $param->{'template'}, $template->{last_error});
        $self->add_stash($request, 'intern');
        return undef;
    }

    # Write config.
    # - Write out initial permanent owners/editors in <role>.dump files.
    # - Write reminder to config file.
    $config =~ s/(\A|\n)[\t ]+(?=\n)/$1/g;    # normalize empty lines
    open my $ifh, '<', \$config;              # open "in memory" file
    my @config = do { local $RS = ''; <$ifh> };
    close $ifh;
    print $lock_fh join '', grep { !/\A\s*(owner|editor)\b/ } @config;

    ## Unlock config file
    $lock_fh->close;

    if ($listname ne $request->{listname}) {
        $self->add_stash($request, 'notice', 'listname_lowercased');
    }

    # Log in stat_table to make statistics
    $log->add_stat(
        'robot'     => $robot_id,
        'list'      => $listname,
        'operation' => 'apply_template_to_list',
        'parameter' => '',
        'mail'      => $request->{sender},
    );

    $list->save_config($sender);
    return 1;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sympa::Request::Handler::apply_template_to_list - apply_template_to_list request handler

=head1 DESCRIPTION

TBD.

=head1 HISTORY

L<Sympa::Request::Handler::apply_template_to_list> appeared on Sympa 6.2.46.

=cut
