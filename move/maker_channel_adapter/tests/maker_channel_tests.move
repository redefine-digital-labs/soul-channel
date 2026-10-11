#[test_only]
module maker_channel_adapter::maker_channel_tests;
use maker_channel_adapter::maker_channel::{Self as adapter,Authority,Goods,AgencyAuthority1,AgencyRevision1,Work};
use soul_channel::agreement::{Self as channel,Instance,AdminCap,Agreement};
use sui::balance;
use std::string;
use sui::test_scenario::{Self,Scenario};
use sui::coin;
use sui::clock::{Self,Clock};
use soulidity_foundation::economics::{Self,Config,Admin};
use soulidity_foundation::package_roles;
use soulidity_foundation::revenue;
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Product,Control,Session};
use soulidity_maker_manufacturing::maker_factory as factory;
use soulidity_maker_manufacturing::maker_release as release;
use soulidity_maker_manufacturing::maker_metadata as metadata;
use soulidity_maker_publication::output_data as output;
use soulidity_content_kinds::content_kind_registry::{Self as kinds,KindRegistry};
use soulidity_content_kinds::document_policy;
use soulidity_maker_manufacturing::maker_player::{Self as player,Player};
use soulidity_maker_manufacturing::manufacturing_storage_fixture as storage;
use soulidity_model::policy::{Self,Source};
use soulidity_model::components::{Self,Item};
use soulidity_visual::visual;
use soulidity_origin_protocol::producer_origin::{Self as origin,Snapshot};
use walrus::system::System;
use walrus::test_node::TestStorageNode;
public struct USD has drop {}
/// Actual private execution markers of this non-Soul producer.
public struct Adapter has drop {}
public struct Revision1 has drop {}
public struct Revision2 has drop {}
public struct PhysicalProducer has drop {}
public struct PhysicalRevision1 has drop {}
/// Private typed test producer. Its material quota is distinct from OC supply.
public struct Registry has key,store {id:UID,product:ID,issued:u64,cap:u64,attempts:vector<vector<u8>>}
public struct Target has key,store {id:UID,origin:Snapshot,sources:vector<Source>,items:vector<Item>}
public struct F {sc:Scenario,cfg:Config<USD>,admin:Admin,p:Product<USD>,control:Control,system:System,nodes:vector<TestStorageNode>,clock:Clock,paid:bool}
fun h(n:u8):vector<u8>{vector::tabulate!(32,|_|n)}
fun scene():visual::Scene{visual::scene(1024,1024,visual::signed(false,0),visual::signed(false,0),0,h(14),b"body",b"pose",vector[b"free"],vector[visual::track(b"main",0,false)],vector[],vector[visual::anchor(b"root",vector[],visual::signed(false,0),visual::signed(false,0))],vector[])}
fun definition():policy::Definition{definition_at(b"style",11)}
fun pack_definition():policy::Definition{definition_at(b"pack-style",13)}
fun definition_at(style:vector<u8>,image:u8):policy::Definition{
 let f=visual::fragment(b"image",h(image),b"image/png",1024,1024,1024,0,0,1024,1024,512000,512000,b"main",0,b"root",visual::transform(visual::signed(false,0),visual::signed(false,0),1000000,visual::signed(false,0)),1000000,0,option::none(),option::none(),option::none(),vector[]);
 policy::definition(b"free",b"item",style,2,h(image),h(12),visual::representation(&scene(),1024,1024,vector[f],vector[]),2,policy::layout(false,0,false,0,1000000,0,vector[]),policy::bounds(0,0,1000000,1000000,0,vector[]),vector[],vector[],true)
}
/// Bootstrap and Walrus BLS certification are explicitly VM fixtures.
/// Subsequent Product/Control/Catalog/System/Coin/session paths are production functions.
fun setup(paid:bool):F{
 let mut sc=test_scenario::begin(@0xa);let(nodes,clock)=storage::bootstrap(&mut sc);kinds::init_for_testing(sc.ctx());let mut system:System=sc.take_shared();let(mut cfg,mut admin)=economics::new_config_for_testing<USD>(1000,500,if(paid)7 else 0,@0xf,sc.ctx());
 catalog::bootstrap_for_testing(&mut cfg,&mut admin);release::bootstrap_for_testing(&mut cfg,&mut admin);let rev=economics::revision(&cfg);let hash=economics::commitment(&cfg);release::install(&mut cfg,&mut admin,&system,h(80),h(81),rev,hash,sc.ctx());let rev=economics::revision(&cfg);let hash=economics::commitment(&cfg);economics::set_primary_enabled(&mut cfg,&mut admin,rev,hash,true);let rev=economics::revision(&cfg);let hash=economics::commitment(&cfg);release::activate(&mut cfg,&mut admin,&system,rev,hash);
 assert!(economics::native_snapshot(&cfg).is_none() && !package_roles::pinned(&economics::role(&cfg,0)),100);factory::create_maker(&cfg,0,&system,sc.ctx());let config=economics::share_config_for_testing(cfg,admin,sc.ctx());test_scenario::return_shared(system);sc.next_tx(@0xa);
 let cfg:Config<USD> =sc.take_shared_by_id(config);let admin:Admin=sc.take_from_sender();let mut p:Product<USD> =sc.take_shared();let mut control:Control=sc.take_from_sender();let mut system:System=sc.take_shared();
 let kinds:KindRegistry=sc.take_shared();let output=output::policy(b"default",false,vector[],h(14),true,vector[],vector[output::initial_rule(&kinds,0,document_policy::soul_doc_name(),3,0),output::initial_rule(&kinds,1,document_policy::memory_name(),3,0)]);test_scenario::return_shared(kinds);let seed=catalog::with_physical_route(catalog::with_outputs(adapter::configure_version(catalog::version(h(1),h(2),0,0,if(paid)1 else 0,if(paid)1000 else 0,0,0,0,@0xd,soulidity_maker_terms::maker_resale::rates(0,0),vector[b"free"],vector[],vector[],vector[],scene())),vector[output]),PhysicalProducer{},PhysicalRevision1{});
 let mut m=metadata::start(&p,&mut control,&cfg,0,seed,&system,sc.ctx());metadata::append_definitions(&mut m,&p,&mut control,&cfg,vector[definition()],&system,0,sc.ctx());let hash=metadata::policy_hash(&m);let living=storage::blob(&mut system,100,false,true,sc.ctx());let manifest=storage::blob(&mut system,101,false,true,sc.ctx());let mut draft=metadata::begin_publication(m,&p,&mut control,&cfg,1,hash,release::author(b"Independent",vector[],vector[],b"license",h(3)),living,manifest,&system,sc.ctx());let blob=storage::blob(&mut system,102,false,true,sc.ctx());release::append(&mut draft,&p,&mut control,&cfg,h(11),false,h(11),blob,&system,0,sc.ctx());release::finish(draft,&mut p,&mut control,&cfg,&system,1,sc.ctx());
 F{sc,cfg,admin,p,control,system,nodes,clock,paid}
}

public struct ManagedF {sc:Scenario,cfg:Config<USD>,admin:Admin,p:Product<USD>,authority:Authority,system:System,nodes:vector<TestStorageNode>,clock:Clock,paid:bool,i:Instance<USD>,cap:AdminCap,a:Agreement<Product<USD>,USD,AgencyAuthority1,AgencyRevision1>}
fun managed(paid:bool):ManagedF {
 let F{mut sc,cfg,admin,mut p,control,system,nodes,clock,paid}=setup(paid);
 let id=adapter::enroll(&mut p,control,sc.ctx());sc.next_tx(@0xa);let authority:Authority=sc.take_shared_by_id(id);
 let mut owner=tx_context::new_from_hint(@0xb,9000,0,0,0);let(i,cap)=channel::create<USD>(&mut owner);
 let a=adapter::offer(&i,&cap,&p,&authority,@0xb,@0xd,20,if(paid)1118 else 0,if(paid)1000 else 0,0,5,&mut owner);
 sc.next_tx(@0xa);ManagedF{sc,cfg,admin,p,authority,system,nodes,clock,paid,i,cap,a}
}
fun accept(f:&mut ManagedF){let exact=channel::commitment(&f.a);let ManagedF{sc,p,authority,i,a,cfg:_,admin:_,system:_,nodes:_,clock:_,paid:_,cap:_}=f;adapter::accept(i,a,p,authority,exact,0,sc.ctx())}
fun execute(f:&mut ManagedF,attempt:u8,value:u64):ID {
 let expiry=clock::timestamp_ms(&f.clock)+1000;let exact=channel::commitment(&f.a);let expected=channel::generation(&f.a);
 let ManagedF{sc,p,authority,i,a,cfg,admin:_,system,nodes:_,clock,paid:_,cap:_}=f;
 let payment=coin::mint_for_testing<USD>(value,sc.ctx());
 adapter::manufacture(i,a,p,authority,cfg,string::utf8(b"Goods"),h(attempt),expiry,expected,exact,payment,vector[policy::definition_hash(&definition())],system,clock,sc.ctx())
}
fun start_work(f:&mut ManagedF,attempt:u8,value:u64):Work<USD>{
 let expiry=clock::timestamp_ms(&f.clock)+1000;let exact=channel::commitment(&f.a);let expected=channel::generation(&f.a);
 let ManagedF{sc,p,authority,i,a,cfg,admin:_,system,nodes:_,clock,paid:_,cap:_}=f;let payment=coin::mint_for_testing<USD>(value,sc.ctx());
 adapter::start_for_testing(i,a,p,authority,cfg,string::utf8(b"Goods"),h(attempt),expiry,expected,exact,payment,system,clock,sc.ctx())
}
fun fulfill(f:&mut ManagedF,work:&mut Work<USD>){let ManagedF{sc,p,authority,a,i:_,cfg:_,admin:_,system:_,nodes:_,clock:_,paid:_,cap:_}=f;adapter::fulfill_for_testing(work,p,authority,a,vector[policy::definition_hash(&definition())],sc.ctx())}
fun close(f:&mut ManagedF,work:Work<USD>){let ManagedF{sc,p,authority,i,a,cfg,admin:_,system,nodes:_,clock,paid:_,cap:_}=f;adapter::close_for_testing(i,a,p,authority,cfg,work,system,clock,sc.ctx());}
fun rotate(f:&mut ManagedF,next:address){let generation=catalog::managed_generation(&f.p);let ManagedF{sc,p,authority,i:_,a:_,cfg:_,admin:_,system:_,nodes:_,clock:_,paid:_,cap:_}=f;adapter::handover(p,authority,generation,next,sc.ctx());}
fun end(f:ManagedF){let ManagedF{mut sc,cfg,admin,p,authority,system,nodes,clock,paid:_,i,cap,a}=f;test_scenario::return_shared(cfg);test_scenario::return_shared(p);test_scenario::return_shared(authority);test_scenario::return_shared(system);test_scenario::return_to_address(@0xa,admin);nodes.do!(|node|node.destroy());clock::destroy_for_testing(clock);channel::destroy_for_testing(a);balance::destroy_for_testing(channel::destroy_instance_for_testing(i,cap));sc.end();}
#[test]
fun real_paid_factory_channel_closure_and_beneficiary_delivery(){
 let mut f=managed(true);accept(&mut f);f.sc.next_tx(@0xb);let id=execute(&mut f,30,1118);
 assert!(channel::income(&f.i)==111 && channel::used(&f.a)==1 && channel::completed(&f.a)==1 && catalog::issued_count(&f.p,1,policy::definition_hash(&definition()))==1 && catalog::wallet_completes(&f.p,1,@0xb)==1,101);
 assert!(revenue::balance(catalog::income(&f.p))==900 && revenue::balance(economics::income(&f.cfg))==107,102);
 f.sc.next_tx(@0xd);let g:Goods=f.sc.take_from_sender_by_id(id);assert!(adapter::goods_sources(&g).length()==1 && adapter::goods_items(&g).length()==1,103);f.sc.return_to_sender(g);end(f)
}
#[test,expected_failure(abort_code=11,location=soulidity_maker_manufacturing::maker_catalog)]
fun R1_real_source_handover_before_accept_refused(){let mut f=managed(false);rotate(&mut f,@0xe);accept(&mut f);end(f)}
#[test,expected_failure(abort_code=11,location=soulidity_maker_manufacturing::maker_catalog)]
fun stale_authorize_after_real_source_handover_refused(){let mut f=managed(false);accept(&mut f);rotate(&mut f,@0xe);f.sc.next_tx(@0xb);execute(&mut f,30,0);end(f)}
#[test,expected_failure(abort_code=11,location=soulidity_maker_manufacturing::maker_catalog)]
fun stale_fulfillment_after_real_source_handover_refused(){let mut f=managed(false);accept(&mut f);f.sc.next_tx(@0xb);let mut work=start_work(&mut f,30,0);f.sc.next_tx(@0xa);rotate(&mut f,@0xe);f.sc.next_tx(@0xb);fulfill(&mut f,&mut work);close(&mut f,work);end(f)}
#[test,expected_failure(abort_code=11,location=soulidity_maker_manufacturing::maker_catalog)]
fun R2_real_fulfillment_then_handover_final_closure_refused(){let mut f=managed(false);accept(&mut f);f.sc.next_tx(@0xb);let mut work=start_work(&mut f,30,0);fulfill(&mut f,&mut work);f.sc.next_tx(@0xa);rotate(&mut f,@0xe);f.sc.next_tx(@0xb);close(&mut f,work);end(f)}
#[test,expected_failure(abort_code=11,location=soulidity_maker_manufacturing::maker_catalog)]
fun ABA_handover_does_not_revive_consent(){let mut f=managed(false);accept(&mut f);rotate(&mut f,@0xe);f.sc.next_tx(@0xe);rotate(&mut f,@0xa);f.sc.next_tx(@0xb);execute(&mut f,30,0);end(f)}
#[test,expected_failure(abort_code=9,location=soul_channel::agreement)]
fun cross_transaction_replay_refused(){let mut f=managed(false);accept(&mut f);f.sc.next_tx(@0xb);execute(&mut f,30,0);f.sc.next_tx(@0xb);assert!(channel::completed(&f.a)==1 && catalog::issued_count(&f.p,1,policy::definition_hash(&definition()))==1,104);execute(&mut f,30,0);end(f)}
#[test,expected_failure(abort_code=2,location=soulidity_foundation::economics)]
fun canonical_maker_underpayment_after_channel_split_refused(){let mut f=managed(true);accept(&mut f);f.sc.next_tx(@0xb);let expiry=clock::timestamp_ms(&f.clock)+1000;let mut owner=tx_context::new_from_hint(@0xb,9999,0,0,0);let mut bad=adapter::offer(&f.i,&f.cap,&f.p,&f.authority,@0xb,@0xd,1,1117,1000,0,5,&mut owner);let exact=channel::commitment(&bad);adapter::accept(&f.i,&mut bad,&f.p,&f.authority,exact,0,&tx_context::new_from_hint(@0xa,8888,0,0,0));f.sc.next_tx(@0xb);let exact=channel::commitment(&bad);let ManagedF{sc,p,authority,i,cfg,system,clock,a:_,admin:_,nodes:_,paid:_,cap:_}=&mut f;adapter::manufacture(i,&mut bad,p,authority,cfg,string::utf8(b"Goods"),h(30),expiry,1,exact,coin::mint_for_testing<USD>(1117,sc.ctx()),vector[policy::definition_hash(&definition())],system,clock,sc.ctx());channel::destroy_for_testing(bad);end(f)}
#[test,expected_failure(abort_code=6,location=soulidity_maker_manufacturing::maker_catalog)]
fun original_authored_supply_remains_authoritative(){let mut f=managed(false);accept(&mut f);f.sc.next_tx(@0xb);execute(&mut f,30,0);execute(&mut f,31,0);execute(&mut f,32,0);end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_maker_manufacturing::maker_catalog)]
fun unauthorized_managed_handover_refused(){let mut f=managed(false);f.sc.next_tx(@0xb);rotate(&mut f,@0xe);end(f)}

#[test]
fun producer_and_channel_paused_exits_release_actual_control_and_income(){
 let mut f=managed(true);accept(&mut f);f.sc.next_tx(@0xb);execute(&mut f,30,1118);
 pause_channel(&mut f);
 let service=withdraw_channel(&mut f,111);assert!(coin::burn_for_testing(service)==111,120);
 f.sc.next_tx(@0xa);let ManagedF{mut sc,mut cfg,mut admin,mut p,mut authority,system,nodes,clock,paid:_,i,cap,a}=f;
 adapter::pause_for_testing(&mut p,&mut authority);
 let rev=economics::revision(&cfg);let hash=economics::commitment(&cfg);economics::set_enabled(&mut cfg,&mut admin,rev,hash,false);
 let generation=catalog::managed_generation(&p);adapter::release(&mut p,authority,generation,sc.ctx());
 assert!(catalog::managed_generation(&p)==generation+1,121);sc.next_tx(@0xa);let mut control:Control=sc.take_from_sender();
 let expected=revenue::revision(catalog::income(&p));catalog::withdraw_income(&mut p,&mut control,expected,900,@0xa,h(70),sc.ctx());
 let expected=revenue::revision(economics::income(&cfg));economics::withdraw_income(&mut cfg,&mut admin,expected,107,@0xa,h(71),sc.ctx());
 assert!(revenue::balance(catalog::income(&p))==0 && revenue::balance(economics::income(&cfg))==0,122);
 sc.next_tx(@0xa);let c1:sui::coin::Coin<USD> =sc.take_from_sender();let c2:sui::coin::Coin<USD> =sc.take_from_sender();assert!(coin::burn_for_testing(c1)+coin::burn_for_testing(c2)==1007,123);
 test_scenario::return_shared(cfg);test_scenario::return_shared(p);test_scenario::return_shared(system);sc.return_to_sender(admin);sc.return_to_sender(control);nodes.do!(|node|node.destroy());clock::destroy_for_testing(clock);channel::destroy_for_testing(a);assert!(balance::destroy_for_testing(channel::destroy_instance_for_testing(i,cap))==0,124);sc.end();
}
#[test]
fun release_free_transfer_return_and_reenrollment_increments_generation(){
 let f=managed(false);let ManagedF{mut sc,cfg,admin,mut p,authority,system,nodes,clock,paid:_,i,cap,a}=f;
 let previous=catalog::managed_generation(&p);adapter::release(&mut p,authority,previous,sc.ctx());sc.next_tx(@0xa);
 let control:Control=sc.take_from_sender();let id=object::id(&control);transfer::public_transfer(control,@0xe);sc.next_tx(@0xe);
 let control:Control=sc.take_from_sender_by_id(id);transfer::public_transfer(control,@0xa);sc.next_tx(@0xa);let control:Control=sc.take_from_sender_by_id(id);
 let aid=adapter::enroll(&mut p,control,sc.ctx());assert!(catalog::managed_generation(&p)==previous+2,125);sc.next_tx(@0xa);let authority:Authority=sc.take_shared_by_id(aid);
 test_scenario::return_shared(authority);test_scenario::return_shared(cfg);test_scenario::return_shared(p);test_scenario::return_shared(system);sc.return_to_sender(admin);nodes.do!(|node|node.destroy());clock::destroy_for_testing(clock);channel::destroy_for_testing(a);balance::destroy_for_testing(channel::destroy_instance_for_testing(i,cap));sc.end();
}
#[test,expected_failure(abort_code=11,location=soulidity_maker_manufacturing::maker_catalog)]
fun released_old_authority_instance_cannot_accept(){
 let f=managed(false);let ManagedF{mut sc,cfg,admin,mut p,authority,system,nodes,clock,paid,i,cap,a}=f;
 let previous=catalog::managed_generation(&p);adapter::release(&mut p,authority,previous,sc.ctx());sc.next_tx(@0xa);let control:Control=sc.take_from_sender();let aid=adapter::enroll(&mut p,control,sc.ctx());sc.next_tx(@0xa);let authority:Authority=sc.take_shared_by_id(aid);
 let mut f=ManagedF{sc,cfg,admin,p,authority,system,nodes,clock,paid,i,cap,a};accept(&mut f);end(f)
}
#[test,expected_failure(abort_code=3,location=soul_channel::agreement)]
fun final_channel_revoke_aborts_after_real_supply_and_payment(){
 let mut f=managed(true);accept(&mut f);f.sc.next_tx(@0xb);let mut work=start_work(&mut f,30,1118);fulfill(&mut f,&mut work);
 assert!(catalog::issued_count(&f.p,1,policy::definition_hash(&definition()))==1 && revenue::balance(catalog::income(&f.p))==900 && channel::income(&f.i)==111,126);
 channel::revoke(&mut f.a,1,f.sc.ctx());close(&mut f,work);end(f)
}
#[test,expected_failure(abort_code=10,location=soul_channel::agreement)]
fun final_channel_pause_aborts_after_real_supply_and_payment(){
 let mut f=managed(true);accept(&mut f);f.sc.next_tx(@0xb);let mut work=start_work(&mut f,30,1118);fulfill(&mut f,&mut work);
 pause_channel(&mut f);close(&mut f,work);end(f)
}

fun pause_channel(f:&mut ManagedF){let ManagedF{sc,i,cap,cfg:_,admin:_,p:_,authority:_,system:_,nodes:_,clock:_,paid:_,a:_}=f;channel::set_paused(i,cap,true,sc.ctx())}
fun withdraw_channel(f:&mut ManagedF,amount:u64):sui::coin::Coin<USD>{let ManagedF{sc,i,cap,cfg:_,admin:_,p:_,authority:_,system:_,nodes:_,clock:_,paid:_,a:_}=f;channel::withdraw(i,cap,amount,sc.ctx())}
