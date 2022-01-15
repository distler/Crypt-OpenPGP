use strict;
use Test::More;

use Crypt::OpenPGP::Plaintext;
use Crypt::OpenPGP::UserID;
use Crypt::OpenPGP::Buffer;
use Crypt::OpenPGP::Constants qw( PGP_PKT_USER_ID PGP_PKT_PLAINTEXT );

use_ok 'Crypt::OpenPGP::PacketFactory';

## 184 bytes
my $text = <<TEXT;
we are the synchronizers
send messages through time code
midi clock rings in my mind
machines gave me some freedom
synthesizers gave me some wings
they drop me through 12 bit samplers
TEXT

my $id = 'Foo Bar <foo@bar.com>';

my @pkt;
push @pkt, # Signature packet
"\x89\x00\xb7\x04\x13\x01\x08\x00\x21\x05\x02\x54\xe5" .
"\xb8\x55\x02\x1b\x03\x05\x0b\x09\x08\x07\x02\x06\x15" .
"\x08\x09\x0a\x0b\x02\x04\x16\x02\x03\x01\x02\x1e\x01" .
"\x02\x17\x80\x00\x0a\x09\x10\x15\x3d\xac\x75\x59\x5e" .
"\x1b\x76\xf1\x57\x03\xfd\x1c\x76\x32\xd0\x24\xec\xbc" .
"\x29\x57\x1e\xd4\xeb\xcb\xab\xb8\xc2\x3f\xb2\xcd\x0f" .
"\xd6\x82\x36\xdc\x38\x7f\xd3\xa7\x3f\x07\x9b\x0a\x8a" .
"\x04\x63\x3d\x78\x07\x18\xed\x4a\xea\x7c\x32\xfa\x66" .
"\x47\xb9\x82\xce\x62\x2b\x2b\xc6\x7e\x05\x55\xc0\xbf" .
"\xdb\x18\xc1\xb3\xb9\x63\xb9\x73\xa4\x1f\x2c\x99\xf7" .
"\x8a\xc6\x43\xc6\xa0\x63\x7f\x83\x61\x99\x58\xf6\x23" .
"\xe7\x88\xf3\x01\x01\x0c\x4b\x97\x68\x5f\x88\xde\xaa" .
"\x75\xcf\xd4\x0a\x20\xb3\x3f\x70\x0b\xae\xd5\x53\xad" .
"\xe5\x0e\x39\x4b\x32\xb2\x65\xdc\xe6\x0d\x13\xf0\x6b" .
"\x72\xfa\xb0\x23";

plan tests => 19 + 2*@pkt;

# Saving packets
my $pt = Crypt::OpenPGP::Plaintext->new( Data => $text );
isa_ok $pt, 'Crypt::OpenPGP::Plaintext';
my $ptdata = $pt->save;
my $ser = Crypt::OpenPGP::PacketFactory->save( $pt );
ok $ser, 'save serializes our packet';
# 1 ctb tag, 1 length byte
is length( $ser ) - length( $ptdata ), 2, '2 bytes for header';

# Test pkt_hdrlen override of hdrlen calculation
# Force Plaintext packets to use 2-byte length headers
*Crypt::OpenPGP::Plaintext::pkt_hdrlen =
*Crypt::OpenPGP::Plaintext::pkt_hdrlen = sub { 2 };

$ser = Crypt::OpenPGP::PacketFactory->save( $pt );
ok $ser, 'save serializes our packet';
# 1 ctb tag, 2 length byte
is length( $ser ) - length( $ptdata ), 3, 'now 3 bytes per header';

# Reading packets from serialized buffer
my $buf = Crypt::OpenPGP::Buffer->new;
$buf->append( $ser );
my $pt2 = Crypt::OpenPGP::PacketFactory->parse( $buf );
isa_ok $pt2, 'Crypt::OpenPGP::Plaintext';
is_deeply $pt, $pt2, 'parsing serialized packet yields original';

# Saving multiple packets
my $userid = Crypt::OpenPGP::UserID->new( Identity => $id );
isa_ok $userid, 'Crypt::OpenPGP::UserID';
$ser = Crypt::OpenPGP::PacketFactory->save( $pt, $userid, $pt );
ok $ser, 'save serializes our packet';

$buf = Crypt::OpenPGP::Buffer->new;
$buf->append( $ser );

my( @pkts, $pkt );
push @pkts, $pkt while $pkt = Crypt::OpenPGP::PacketFactory->parse( $buf );
is_deeply \@pkts, [ $pt, $userid, $pt ],
    'parsing multiple packets gives us back all 3 originals';

# Test finding specific packets
@pkts = ();
$buf->reset_offset;
push @pkts, $pkt
    while $pkt = Crypt::OpenPGP::PacketFactory->parse(
        $buf,
        [ PGP_PKT_USER_ID ]
    );
is_deeply \@pkts, [ $userid ], 'only 1 userid packet found';

@pkts = ();
$buf->reset_offset;
push @pkts, $pkt
    while $pkt = Crypt::OpenPGP::PacketFactory->parse(
        $buf,
        [ PGP_PKT_PLAINTEXT ]
    );
is_deeply \@pkts, [ $pt, $pt ], '2 plaintext packets found';

# Test finding, but not parsing, specific packets

@pkts = ();
$buf->reset_offset;
push @pkts, $pkt
    while $pkt = Crypt::OpenPGP::PacketFactory->parse(
        $buf,
        [ PGP_PKT_PLAINTEXT, PGP_PKT_USER_ID ],
        [ PGP_PKT_USER_ID ],
    );
is @pkts, 3, 'found all 3 packets';
isa_ok $pkts[0], 'HASH';
ok $pkts[0]->{__unparsed}, 'plaintext packets are unparsed';
is_deeply $pkts[1], $userid, 'userid packets are parsed';
isa_ok $pkts[2], 'HASH';
ok $pkts[2]->{__unparsed}, 'plaintext packets are unparsed';

use Data::Dumper;
my $i = 0;
do {
	$buf->empty();
	$buf->put_bytes($pkt[$i]);
	my $parsed = Crypt::OpenPGP::PacketFactory->parse($buf);
	isnt $parsed, undef, "Parsed packet $i";
	my $saved = Crypt::OpenPGP::PacketFactory->save($parsed);
	is $saved, $pkt[$i], "parse-save roundtrip identical for packet $i";
} while( ++$i < @pkt );
