#-*-perl-*-
#$Id$
use Test::More qw(no_plan);
use Test::Exception;
use Module::Build;
use lib '../lib';
use REST::Neo4p;
use strict;
use warnings;
no warnings qw(once);

my $build;
eval {
    $build = Module::Build->current;
};
my $TEST_SERVER = $build ? $build->notes('test_server') : 'http://127.0.0.1:7474';
my $num_live_tests = 1;

my $not_connected;
eval {
  REST::Neo4p->connect($TEST_SERVER);
};
if ( my $e = REST::Neo4p::CommException->caught() ) {
  $not_connected = 1;
  diag "Test server unavailable : ".$e->message;
}

use_ok ('REST::Neo4p::Constraint');

my ($person_pc, $pet_pc, $reln_pc, $reln_c, $reln_tc);

throws_ok { REST::Neo4p::Constraint->new() } qr/requires tag/, 'no args exception';
throws_ok { REST::Neo4p::Constraint->new('$$blurg') } qr/only alphanumeric/, 'bad tag chars exception';
throws_ok { REST::Neo4p::Constraint::NodeProperty->new('blurg',['not correct']) } qr/not a hashref/, 'dies on bad 2nd (constraints) arg';


ok $person_pc = REST::Neo4p::Constraint::NodeProperty->new('person', 
					   { name => qr/^[A-Z]/,
					     genus => 'Homo',
					     language => '+' }), 'node_property constraint';
ok $pet_pc = REST::Neo4p::Constraint::NodeProperty->new('pet', 
					  { _condition => 'all',
					    name => qr/^[A-Z]/,
					    genus => 'Canis' });

ok $reln_pc = REST::Neo4p::Constraint::RelationshipProperty->new('acquaintance', 
					   { disposition => ['friendly','neutral','antagonistic'] }), 'relationship_property constraint';

ok $reln_c = REST::Neo4p::Constraint::Relationship->new('reln_c',
							{ acquaintance_of => [{'person' => 'person' }] } ), "relationship constraint";

ok $reln_tc = REST::Neo4p::Constraint::RelationshipType->new('reln_tc', 
{ type_list => ['acquaintance_of', 'pet_of']}), 'relationship_type constraint';

isa_ok($_, 'REST::Neo4p::Constraint') for ($person_pc, $pet_pc,
					   $reln_pc, $reln_c, $reln_tc);

is $person_pc->condition, 'only', 'person_pc condition correct (default)';
is $pet_pc->condition, 'all', 'pet_pc condition correct';
ok $pet_pc->set_condition('only'), 'set condition';
is $pet_pc->condition, 'only', 'set condition works';
ok !$pet_pc->constraints->{_condition}, "pet_pc _condition removed from constraint hash";
is_deeply [sort $reln_tc->type_list], [qw( acquaintance_of pet_of )], 'type_list correct';

is $person_pc->tag, 'person', 'person_pc tag correct';
is $pet_pc->tag, 'pet', 'pet_pc tag correct';
is $reln_pc->tag, 'acquaintance', 'reln_pc tag correct';
is $reln_c->tag, 'reln_c', 'reln_c tag correct';
is $reln_tc->tag, 'reln_tc', 'reln_tc tag correct';

is $person_pc->type, 'node_property', 'person_pc type correct';
is $pet_pc->type, 'node_property', 'pet_pc type correct';
is $reln_pc->type, 'relationship_property', 'reln_pc type correct';
is $reln_c->type, 'relationship', 'reln_c type correct';
is $reln_tc->type, 'relationship_type', 'reln_tc type correct';

ok $person_pc->set_priority(1), 'set person_pc priority';
ok $reln_pc->set_priority(20), 'set reln_pc priority';
ok $reln_tc->set_priority(50), 'set reln_tc priority';
is $person_pc->priority, 1, 'person_pc priority set';
is $reln_pc->priority, 20, 'person_pc priority set';
is $reln_tc->priority, 50, 'person_pc priority set';

$person_pc->add_constraint( species => ['sapiens', 'habilis'] );
ok grep(/species/,keys $person_pc->constraints), 'constraint added';

ok $reln_c->add_constraint( acquaintance_of => { 'pet' => 'pet' } ), 'add relationship constraint';
ok $reln_c->add_constraint( pet_of => { 'pet' => 'person' } ), 'add relationship constraint';
is_deeply $reln_c->constraints->{acquaintance_of}, [{'person'=>'person'},{'pet' => 'pet'}], 'relationship constraint added';
is_deeply $reln_c->constraints->{pet_of}, [{'pet' => 'person'}], 'relationship constraint added';

ok $reln_tc->add_constraint('slave_of'), "relationship type added";
is_deeply [$reln_tc->type_list], [qw( acquaintance_of pet_of slave_of )], "relationship type added";

throws_ok { $reln_c->add_constraint( pet_of => { 'slave' => 'person' }) } qr/is not defined/, "bad constraint tag (1) throws";
throws_ok { $reln_c->add_constraint( pet_of => { 'person' => 'insect' }) } qr/is not defined/, "bad constraint tag (2) throws";

throws_ok { $person_pc->get_constraint('pet') } 'REST::Neo4p::ClassOnlyException', 'get_constraint() is class-only';

isa_ok(REST::Neo4p::Constraint->get_constraint('pet'), 'REST::Neo4p::Constraint');
is(REST::Neo4p::Constraint->get_constraint('pet')->tag, 'pet', 'got pet constraint');

# test validation - property constraints

my $c1 = REST::Neo4p::Constraint::NodeProperty->new(
  'c1',
  {
    name => '',
    rank => [],
    serial_number => qr/^[0-9]+$/,
    army_of => 'one',
    options => [qr/[abc]/]
    
   }
 );

my @propset;
# 1
# valid for all, only
# invalid for none
push @propset, 
  [
    {
      name => 'Jones',
      rank => 'Corporal',
      serial_number => '147800934',
      army_of => 'one'
     },[1, 1, 0]
    ];
# 2
# valid for all, only
# invalid for none
push @propset, [
  {
    name => 'Jones',
    serial_number => '147800934',
    army_of => 'one'
   }, [1,1,0] 
];

# 3
# valid for all
# invalid for only, none
push @propset, [
  {
    name => 'Jones',
    serial_number => '147800934',
    army_of => 'one',
    extra => 'value'
   }, [1,0,0]
];

# 4
# invalid for all, only
# invalid for none
push @propset, [
  {
    name => 'Jones',
    rank => 'Corporal',
    serial_number => 'THX1138',
    army_of => 'one'
   }, [0,0,0]
];

# 5
# invalid for all, only
# valid for none
push @propset, [
  {
    different => 'altogether'
  }, [0,0,1]
];

# 6
# valid for all, only
# invalid for none
push @propset, [
   {
     name => 'Jones',
     rank => 'Corporal',
     serial_number => '147800934',
     army_of => 'one',
     options => 'a'
    }, [1,1,0]
];

# 7
# invalid for all, only, none
push @propset, [
  {
    name => 'Jones',
    rank => 'Corporal',
    serial_number => '147800934',
    options => 'e'
   }, [0,0,0]
];
$DB::single=1;
my $ctr=0;
foreach (@propset) {
  my $propset = $_->[0];
  my $expected = $_->[1];
  $ctr++;
  $c1->set_condition('all');
  is $c1->validate($propset), $expected->[0], "propset $ctr : all";
  $c1->set_condition('only');
  is $c1->validate($propset), $expected->[1], "propset $ctr : only";
  $c1->set_condition('none');
  is $c1->validate($propset), $expected->[2], "propset $ctr : none";
}

SKIP : {
  skip 'no local connection to neo4j', $num_live_tests if $not_connected;

}
