package Games::Hangman;

# DATE
# VERSION

#use Color::ANSI::Util qw(ansibg ansifg);
use Module::List qw(list_modules);
use Module::Load;
use Term::ReadKey;
use Text::WideChar::Util qw(wrap);
use Time::HiRes qw(sleep);

use 5.010001;
use Mo qw(build default);
use experimental 'smartmatch';

has list              => (is => 'rw');
has _list_obj         => (is => 'rw');
has list_type         => (is => 'rw'); # either (w)ord or (p)hrase
has min_len           => (is => 'rw');
has current_word      => (is => 'rw');
has num_words         => (is => 'rw', default=>0); # words that have been played
has num_guessed_words => (is => 'rw', default=>0); # have been guessed correctly
has guessed_letters   => (is => 'rw');
has num_wrong_letters => (is => 'rw');

my @pics = (
    [
        "   ____     ",
        "  |    |    ",
        "  |         ",
        "  |         ",
        "  |         ",
        "  |         ",
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
    [
        "   ____     ",
        "  |    |    ",
        "  |    o    ",
        "  |         ",
        "  |         ",
        "  |         ",
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
    [
        "   ____     ",
        "  |    |    ",
        "  |    o    ",
        "  |   /     ",
        "  |         ",
        "  |         ",
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
    [
        "   ____     ",
        "  |    |    ",
        "  |    o    ",
        "  |   /|    ",
        "  |         ",
        "  |         ",
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
    [
        "   ____     ",
        "  |    |    ",
        "  |    o    ",
        '  |   /|\   ',
        "  |         ",
        "  |         ",
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
    [
        "   ____     ",
        "  |    |    ",
        "  |    o    ",
        '  |   /|\   ',
        "  |    |    ",
        "  |         ",
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
    [
        "   ____     ",
        "  |    |    ",
        "  |    o    ",
        '  |   /|\   ',
        "  |    |    ",
        "  |   /     ",
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
    [
        "   ____     ",
        "  |    |    ",
        "  |    o    ",
        '  |   /|\   ',
        "  |    |    ",
        '  |   / \   ',
        " _|_        ",
        "|   |______ ",
        "|          |",
        "|__________|"],
);

sub _word_term {
    my $self = shift;
    $self->list_type eq 'p' ? 'phrase' : 'word';
}

sub draw {
    my ($self, $message1, $message2) = @_;
    state $drawn = 0;
    state $buf = "";

    # move up to original row position
    if ($drawn) {
        # count the number of newlines
        my $num_nls = 0;
        $num_nls++ while $buf =~ /\n/g;
        printf "\e[%dA", $num_nls;
    }

    $buf = "";

    # draw the hung man + right pane
    my $pic = $pics[ $self->num_wrong_letters ];
    for my $i (0..@$pic-1) {
        $buf .= $pic->[$i];
        if ($i == 1) {
            $buf .= sprintf("%-6s #: %4d", ucfirst($self->_word_term),
                            $self->num_words);
        } elsif ($i == 2) {
            $buf .= sprintf("Guessed : %-26s", $self->guessed_letters);
        } elsif ($i == 3) {
            my $n = $self->num_words;
            $buf .= sprintf("Average : %3.0f%%",
                            $n>1 ? $self->num_guessed_words/($n-1)*100.0 : 0);
        }
        $buf .= "\n";
    }
    $buf .= "\n";

    my $word = $self->current_word;
    my ($termwidth, $wordwidth);
    {
        if (eval "require Term::Size") {
            ($termwidth, undef) = Term::Size::chars();
        } else {
            $termwidth = 80;
        }
        $wordwidth = $termwidth-8;
        $word = wrap($word, $wordwidth);
        $word =~ s/\n/        /g;
        my $guessed = $self->guessed_letters;
        $word =~ s{([A-Za-z])}
                  {my $l = lc($1); index($guessed, $l) >= 0 ? $1 : "-"}egx;
    }

    $buf .= sprintf("List  : %-30s\n", $self->list);
    $buf .= sprintf("%-6s: %-${wordwidth}s\n",
                    ucfirst($self->_word_term), $word);
    $buf .= sprintf("Guess : %-60s\n%-60s\n", $message1 // '', $message2 // '');
    print $buf;
    $drawn++;
}

# borrowed from Games::2048
sub read_key {
    my $self = @_;

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

sub new_word {
    my $self = shift;

    my $word;
    if ($self->list_type eq 'phrase') {
        $word = $self->_list_obj->random_phrase;
    } else {
        $word = $self->_list_obj->random_word;
    }

    $self->current_word($word);
    $self->num_words( $self->num_words+1 );
    $self->guessed_letters('');
    $self->num_wrong_letters(0);
    $self->draw;
}

sub BUILD {
    my $self = shift;

    # pick word-/phraselist
    {
        my $wmods = list_modules("Games::Word::Wordlist::",
                                 {list_modules=>1, recurse=>1});
        my @wmods = keys %$wmods; s/^Games::Word::Wordlist::// for @wmods;
        my $pmods = list_modules("Games::Word::Phraselist::",
                                 {list_modules=>1, recurse=>1});
        my @pmods = keys %$pmods; s/^Games::Word::Phraselist::// for @pmods;
        my ($list, $type) = @_;
        if ($self->list) {
            $list = $self->list;
            if ($list =~ s/^Games::Word::Wordlist:://) {
                $type = 'w';
            } elsif ($list =~ s/^Games::Word::Phraselist:://) {
                $type = 'p';
            } else {
                $type = '';
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
            if ($type eq 'w') {
                if (($ENV{LANG} // "") =~ /^id/ && "KBBI" ~~ @wmods) {
                    $list = "KBBI";
                } else {
                    if (@wmods > 1) {
                        @wmods = grep {$_ ne 'KBBI'} @wmods;
                    }
                    $list = $wmods[rand @wmods];
                }
            } else {
                if (($ENV{LANG} // "") =~ /^id/ && "Proverb::KBBI" ~~ @pmods) {
                    $list = "Proverb::KBBI";
                } else {
                    if (@pmods > 1) {
                        @pmods = grep {$_ ne 'Proverb::KBBI'} @pmods;
                    }
                    $list = $pmods[rand @pmods];
                }
            }
        }
        my $mod = ($type eq 'w' ? "Games::Word::Wordlist::$list" :
                       "Games::Word::Phraselist::$list");;
        load $mod;
        $self->list_type($type);
        $self->list($list);
        $self->_list_obj($mod->new);
    }

}

sub init {
    my $self = shift;
    $SIG{INT}     = sub { $self->cleanup; exit 1 };
    $SIG{__DIE__} = sub { warn shift; $self->cleanup; exit 1 };
    ReadMode "cbreak";

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

sub word_guessed {
    my $self = shift;
    my $word = $self->current_word;
    my $guessed = $self->guessed_letters;
    while ($word =~ /([A-Za-z])/g) {
        my $l = lc($1);
        if (index($guessed, $l) < 0) {
            return 0;
        }
    }
    1;
}

sub run {
    my $self = shift;

    $self->init;
  WORD:
    while (1) {
        $self->new_word;
        $self->draw;
      KEY:
        while (1) {
            my $key = $self->read_key;
            if (!defined($key)) {
                sleep 0.1;
                next KEY;
            } elsif ($key =~ /\A[A-Za-z]\z/) {
                my $guessed = $self->guessed_letters;
                my $l = lc $key;
                if (index($guessed, $l) >= 0) {
                    $self->draw("You already guess letter '$l'");
                    next KEY;
                }
                my $word = lc($self->current_word);
                $self->guessed_letters(join("", sort(split('',$guessed),$l)));
                if (index($word, $l) >= 0) {
                    # correct letter
                    if ($self->word_guessed) {
                        $self->draw("Correct! Press q to quit, or Space ".
                                        "for the next word");
                        $self->num_guessed_words( $self->num_guessed_words+1 );
                        my $key;
                        while (1) {
                            $key = $self->read_key(1);
                            if (!defined($key)) {
                                sleep 0.1; next;
                            } elsif ($key eq 'q' || $key eq 'Q') {
                                last WORD;
                            } elsif ($key eq ' ') {
                                next WORD;
                            }
                        }
                    } else {
                        $self->draw;
                    }
                } else {
                    # wrong letter
                    $self->num_wrong_letters($self->num_wrong_letters+1);
                    if ($self->num_wrong_letters >= 7) {
                        $self->draw(
                            substr("Sorry, the " . $self->_word_term .
                                       " is: " . $self->current_word,
                                   0, 60),
                            "Press q to quit, or Space for the next word",
                        );
                        while (1) {
                            $key = $self->read_key(1);
                            if (!defined($key)) {
                                sleep 0.1; next;
                            } elsif ($key eq 'q' || $key eq 'Q') {
                                last WORD;
                            } elsif ($key eq ' ') {
                                next WORD;
                            }
                        }
                    } else {
                        $self->draw;
                    }
                }
            } else {
                $self->draw("Not a valid guess");
            }
        }
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
