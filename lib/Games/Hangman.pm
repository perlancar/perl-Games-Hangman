package Games::ArrangeNumber;

# DATE
# VERSION

#use Color::ANSI::Util qw(ansibg ansifg);
use Module::List qw(list_modules);
use Term::ReadKey;
use Time::HiRes qw(sleep);

use 5.010001;
use Mo qw(build default);
use experimental 'smartmatch';

has list              => (is => 'rw');
has list_type         => (is => 'rw'); # either (w)ord or (p)hrase
has min_len           => (is => 'rw');
has num_words         => (is => 'rw'); # number of words that have been played
has num_guessed_words => (is => 'rw'); # number that have been guessed correctly
has guessed_letters   => (is => 'rw');
has num_wrong_letters => (is => 'rw');

sub draw_board {
    my $self = shift;
    state $drawn = 0;
    state $buf = "";

    return unless $self->needs_redraw;

    # move up to original row position
    if ($drawn) {
        # count the number of newlines
        my $num_nls = 0;
        $num_nls++ while $buf =~ /\n/g;
        printf "\e[%dA", $num_nls;
    }

    my $s = $self->board_size;
    my $w = $s > 3 ? 2 : 1; # width of number
    $buf = "";
    $buf .= "How to play: press arrow keys to arrange the numbers.\n";
    $buf .= "  Press R to restart. Q to quit.\n";
    $buf .= "\n";
    $buf .= sprintf("Moves: %-4d | Time: %-5d\n", $self->num_moves,
                    time-$self->start_time);
    $buf .= $self->_col("border", "  ", (" " x ($s*(4+$w))), "  ");
    $buf .= "\n";
    my $board = $self->board;
    for my $row (@$board) {
        for my $i (1..3) {
            $buf .= $self->_col("border", "  ");
            for my $cell (@$row) {
                my $item = $cell == 0 ? "blank_tile" :
                    $cell % 2 ? "odd_tile" : "even_tile";
                $buf .= $self->_col(
                    $item, sprintf("  %${w}s  ", $i==2 && $cell ? $cell : ""));
            }
            $buf .= $self->_col("border", "  ");
            $buf .= "\n";
        }
    }
    $buf .= $self->_col("border", "  ", (" " x ($s*(4+$w))), "  ");
    $buf .= "\n";
    print $buf;
    $drawn++;
    $self->needs_redraw(0);
}

# borrowed from Games::2048
sub read_key {
    my $self = shift;
    state @keys;

    if (@keys) {
        return shift @keys;
    }

    my $char;
    my $packet = '';
    while (defined($char = ReadKey -1)) {
        $packet .= $char;
    }

    while ($packet =~ m(
                           \G(
                               \e \[          # CSI
                               [\x30-\x3f]*   # Parameter Bytes
                               [\x20-\x2f]*   # Intermediate Bytes
                               [\x40-\x7e]    # Final Byte
                           |
                               .              # Otherwise just any character
                           )
                   )gsx) {
        push @keys, $1;
    }

    return shift @keys;
}

sub new_game {
    my $self = shift;

    my $board;
    while (1) {
        my @num0 = (1 .. ($s ** 2 -1), 0);
        my @num  = shuffle @num0;
        redo if join(",",@num0) eq join(",",@num);
        $board = [];
        while (@num) {
            push @$board, [splice @num, 0, $s];
        }
        last;
    }
    $self->board($board);
    $self->num_moves(0);
    $self->start_time(time());

    $self->needs_redraw(1);
    $self->draw_board;
}

sub init {
    my $self = shift;
    $SIG{INT}     = sub { $self->cleanup; exit 1 };
    $SIG{__DIE__} = sub { warn shift; $self->cleanup; exit 1 };
    ReadMode "cbreak";

    # pick word-/phraselist
    {
        my $wmods = list_modules("Games::Word::Wordlist::",
                                 {list_modules=>1, recurse=>1});
        my @wmods = key %$wmods; s/^Games::Word::Wordlist::// for @wmods;
        my $pmods = list_modules("Games::Word::Phraselist::",
                                 {list_modules=>1, recurse=>1});
        my @pmods = key %$pmods; s/^Games::Word::Phraselist::// for @pmods;
        my ($list, $type) = @_;
        if ($self->list) {
            $list = $self->list;
            if ($list =~ s/^Games::Word::Wordlist:://) {
                $type = 'w';
            } elsif ($list =~ s/^Games::Word::Phraselist:://) {
                $type = 'p';
            }
            if ($type eq 'w') {
                die "Unknown wordlist '$list'\n" unless $list ~~ @wmods;
            } elsif ($type eq 'p') {
                die "Unknown phraselist '$list'\n" unless $list ~~ @pmods;
            } else {
                if ($list ~~ @wmods) {
                    $type = 'w';
                } elsif ($list ~~ @pmods) {
                    $type = 'p';
                } else {
                    die "Unknown word-/phraselist '$list'\n";
                }
            }
        } else {
            $type = rand() > 0.5 ? 'w':'p';
            if (($ENV{LANG} // "") =~ /^id/ && "KBBI" ~~ @wls) {
                $list = $type eq 'w' ? "KBBI" : "Proverb::KBBI";
            } else {
                if ($type eq 'w') {
                    if (@wmods > 1) {
                        @wmods = grep {$_ ne 'KBBI'} @wmods;
                    }
                    $list = $wmods[rand @wmods];
                } else {
                    if (@pmods > 1) {
                        @pmods = grep {$_ ne 'Proverb::KBBI'} @pmods;
                    }
                    $list = $pmods[rand @pmods];
                }
            }
            $self->list_type($type);
            $self->list($list);
        }
        load($type eq 'w' ? "Games::Word::Wordlist::$list" :
             "Games::Word::Phraselist::$list");
    }

    # pick color depth
    #if ($ENV{KONSOLE_DBUS_SERVICE}) {
    #    $ENV{COLOR_DEPTH} //= 2**24;
    #} else {
    #    $ENV{COLOR_DEPTH} //= 16;
    #}
}

sub cleanup {
    my $self = shift;
    ReadMode "normal";
}

# move the blank tile
sub move {
    my ($self, $dir) = @_;

    my $board = $self->board;
    # find the current position of the blank tile
    my ($curx, $cury);
  FIND:
    for my $y (0..@$board-1) {
        my $row = $board->[$y];
        for my $x (0..@$row-1) {
            if ($row->[$x] == 0) {
                $curx = $x;
                $cury = $y;
                last FIND;
            }
        }
    }

    my $s = $self->board_size;
    if ($dir eq 'up') {
        return unless $cury > 0;
        $board->[$cury  ][$curx  ] = $board->[$cury-1][$curx  ];
        $board->[$cury-1][$curx  ] = 0;
    } elsif ($dir eq 'down') {
        return unless $cury < $s-1;
        $board->[$cury  ][$curx  ] = $board->[$cury+1][$curx  ];
        $board->[$cury+1][$curx  ] = 0;
    } elsif ($dir eq 'left') {
        return unless $curx > 0;
        $board->[$cury  ][$curx  ] = $board->[$cury  ][$curx-1];
        $board->[$cury  ][$curx-1] = 0;
    } elsif ($dir eq 'right') {
        return unless $curx < $s-1;
        $board->[$cury  ][$curx  ] = $board->[$cury  ][$curx+1];
        $board->[$cury  ][$curx+1] = 0;
    } else {
        die "BUG: Unknown direction '$dir'";
    }

    $self->num_moves($self->num_moves+1);
    $self->needs_redraw(1);
}

sub run {
    my $self = shift;

    $self->init;
    $self->new_game;
    my $ticks = 0;
  GAME:
    while (1) {
        while (defined(my $key = $self->read_key)) {
            if ($key eq 'q' || $key eq 'Q') {
                last GAME;
            } elsif ($key eq 'r' || $key eq 'R') {
                $self->new_game;
            } elsif ($key eq "\e[D") { # left arrow
                $self->move("right");
            } elsif ($key eq "\e[A") { # up arrow
                $self->move("down");
            } elsif ($key eq "\e[C") { # right arrow
                $self->move("left");
            } elsif ($key eq "\e[B") { # down arrow
                $self->move("up");
            }
        }
        $self->draw_board;
        if ($self->has_won) {
            say "You won!";
            last;
        }
        sleep 1/$self->frame_rate;
        $ticks++;
        $self->needs_redraw(1) if $ticks % $self->frame_rate == 0
    }
    $self->cleanup;
}

# ABSTRACT: A text-based hangman

=for Pod::Coverage ^(.+)$

=head1 SYNOPSIS

 % hangman


=head1 TODO

=over

=item * Record and save high scores

=item * Add some animation

=back


=head1 SEE ALSO

L<hangman>
