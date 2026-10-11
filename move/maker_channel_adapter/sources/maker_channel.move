/// Optional independently owned Maker consumer. Principal explicitly enrolls
/// actual Control; private witnesses never leave this module. Maker stays standalone.
module maker_channel_adapter::maker_channel;
use soul_channel::agreement::{Self as channel,Instance,AdminCap,Agreement,Authorization};
use soulidity_maker_manufacturing::maker_catalog::{Self as maker,Product,Control,Version,Session};
use soulidity_maker_manufacturing::maker_factory as factory;
use soulidity_maker_manufacturing::maker_release as release;
use soulidity_foundation::economics::Config;
use soulidity_origin_protocol::producer_origin::{Self as origin,Snapshot};
use soulidity_model::components::{Self,Item};
use soulidity_model::policy::Source;
use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use walrus::system::System;

public struct AgencyAuthority1 has drop {}
public struct AgencyRevision1 has drop {}
/// No store: only handover/release below can dispose of this shared authority.
public struct Authority has key {id:UID,control:Control}
public struct Goods has key,store {id:UID,origin:Snapshot,sources:vector<Source>,items:vector<Item>}
/// No public function returns this or any completion/witness/token.
public struct Work<phantom C> {authorization:Authorization<Product<C>,C,AgencyAuthority1,AgencyRevision1>,session:Session,goods:Goods,intent:vector<u8>}

public fun configure_version(v:Version):Version {maker::with_execution<AgencyAuthority1,AgencyRevision1,Goods>(v,AgencyAuthority1{},AgencyRevision1{})}
/// Caller must supply its actual owned Control. This is voluntary custody,
/// unrelated to Soul/Standard/Vault and leaves the unmediated Maker path intact.
public fun enroll<C>(p:&mut Product<C>,control:Control,ctx:&mut TxContext):ID {
 let authority=Authority{id:object::new(ctx),control};
 let _=maker::enroll_managed_authority(p,&authority.control,&authority,AgencyAuthority1{},AgencyRevision1{},ctx);
 let id=object::id(&authority);transfer::share_object(authority);id
}
public fun handover<C>(p:&mut Product<C>,authority:&Authority,expected:u64,next:address,ctx:&TxContext):u64 {
 maker::rotate_managed_authority(p,&authority.control,authority,expected,next,AgencyAuthority1{},AgencyRevision1{},ctx)
}
public fun release<C>(p:&mut Product<C>,authority:Authority,expected:u64,ctx:&TxContext) {
 maker::release_managed_authority(p,&authority.control,&authority,expected,AgencyAuthority1{},AgencyRevision1{},ctx);
 let Authority{id,control}=authority;id.delete();transfer::public_transfer(control,ctx.sender())
}
fun guard<C>(p:&Product<C>,authority:&Authority,a:&Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>) {
 let t=channel::terms(a);
 maker::assert_managed_authority(p,&authority.control,authority,channel::source_version(t),channel::source_generation(t),channel::principal(t),AgencyAuthority1{},AgencyRevision1{})
}
public fun offer<C>(i:&Instance<C>,cap:&AdminCap,p:&Product<C>,authority:&Authority,
 agent:address,beneficiary:address,quota:u64,gross_per_unit:u64,commission_bps:u16,starts:u64,expires:u64,ctx:&mut TxContext):Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1> {
 let version=maker::current_version(p);let generation=maker::managed_generation(p);let principal=maker::managed_principal(p);
 maker::assert_managed_authority(p,&authority.control,authority,version,generation,principal,AgencyAuthority1{},AgencyRevision1{});
 channel::offer(i,cap,p,&authority.control,version,generation,principal,agent,beneficiary,channel::issuance(),quota,gross_per_unit,commission_bps,starts,expires,ctx)
}
public fun accept<C>(i:&Instance<C>,a:&mut Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,p:&Product<C>,authority:&Authority,
 exact:vector<u8>,expected:u64,ctx:&TxContext) {
 guard(p,authority,a);
 channel::accept(i,a,p,&authority.control,maker::current_version(p),maker::managed_generation(p),maker::managed_principal(p),AgencyAuthority1{},exact,expected,ctx)
}
fun start<C>(i:&mut Instance<C>,a:&mut Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,p:&mut Product<C>,authority:&Authority,
 cfg:&mut Config<C>,name:String,intent:vector<u8>,expiry:u64,expected:u64,exact:vector<u8>,payment:Coin<C>,system:&System,clock:&Clock,ctx:&mut TxContext):Work<C> {
 guard(p,authority,a);release::assert_current(p,cfg,maker::current_version(p),system);
 let (authorization,net)=channel::authorize(i,a,p,&authority.control,maker::current_version(p),maker::managed_generation(p),maker::managed_principal(p),AgencyAuthority1{},intent,1,expected,exact,payment,ctx);
 // No externally transportable proof: reread producer authority immediately
 // before canonical factory authorization/payment, after Channel settlement.
 guard(p,authority,a);
 let request=factory::request<C,AgencyAuthority1,AgencyRevision1,Goods>(p,cfg,maker::current_version(p),maker::policy_hash(maker::published(p,maker::current_version(p))),name,intent,expiry,AgencyAuthority1{},AgencyRevision1{},system,clock,ctx);
 let snapshot=origin::consume_request<Goods>(request,ctx);
 let goods=Goods{id:object::new(ctx),origin:snapshot,sources:vector[],items:vector[]};
 let session=factory::begin(p,&goods,cfg,snapshot,net,AgencyAuthority1{},AgencyRevision1{},system,clock,ctx);
 Work{authorization,session,goods,intent}
}
fun fulfill<C>(work:&mut Work<C>,p:&mut Product<C>,authority:&Authority,a:&Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,definitions:vector<vector<u8>>,ctx:&mut TxContext) {
 guard(p,authority,a);assert!(!definitions.is_empty(),20);
 definitions.do!(|definition|{
  let(permit,selection)=maker::select(&mut work.session,p,&work.goods,definition,ctx);
  let(source,item)=components::materialize(permit,object::id(&work.goods),ctx);
  work.goods.sources.push_back(source);item.do!(|item|work.goods.items.push_back(item));
  maker::selected(&mut work.session,selection,&work.goods,AgencyAuthority1{},AgencyRevision1{},ctx)
 })
}
fun close<C>(i:&Instance<C>,a:&mut Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,p:&Product<C>,authority:&Authority,
 cfg:&Config<C>,work:Work<C>,system:&System,clock:&Clock,ctx:&TxContext):ID {
 guard(p,authority,a);release::assert_current(p,cfg,maker::current_version(p),system);
 let Work{authorization,session,goods,intent}=work;
 let completion=factory::finish(session,&goods,cfg,AgencyAuthority1{},AgencyRevision1{},system,clock,ctx);
 origin::consume_completion<AgencyAuthority1,AgencyRevision1,Goods>(completion,&goods,&goods.origin,ctx);
 // Source authority reread in the same protected terminal continuation. There
 // is no public complete wrapper accepting a transportable stale business token.
 guard(p,authority,a);
 let beneficiary=channel::beneficiary(channel::terms(a));
 channel::complete(i,a,p,&authority.control,maker::current_version(p),maker::managed_generation(p),maker::managed_principal(p),authorization,ctx.sender(),beneficiary,intent,1,channel::issuance(),AgencyRevision1{},ctx);
 let id=object::id(&goods);transfer::public_transfer(goods,channel::beneficiary(channel::terms(a)));id
}
public fun manufacture<C>(i:&mut Instance<C>,a:&mut Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,p:&mut Product<C>,authority:&Authority,
 cfg:&mut Config<C>,name:String,intent:vector<u8>,expiry:u64,expected:u64,exact:vector<u8>,payment:Coin<C>,definitions:vector<vector<u8>>,system:&System,clock:&Clock,ctx:&mut TxContext):ID {
 let mut work=start(i,a,p,authority,cfg,name,intent,expiry,expected,exact,payment,system,clock,ctx);
 fulfill(&mut work,p,authority,a,definitions,ctx);close(i,a,p,authority,cfg,work,system,clock,ctx)
}
public fun goods_sources(g:&Goods):&vector<Source>{&g.sources}
public fun goods_items(g:&Goods):&vector<Item>{&g.items}

// Test-only split instrumentation exists solely to insert adversarial rotations
// at boundaries that production manufacture encloses. Not production ABI.
#[test_only]
public fun start_for_testing<C>(i:&mut Instance<C>,a:&mut Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,p:&mut Product<C>,authority:&Authority,cfg:&mut Config<C>,name:String,intent:vector<u8>,expiry:u64,expected:u64,exact:vector<u8>,payment:Coin<C>,system:&System,clock:&Clock,ctx:&mut TxContext):Work<C>{start(i,a,p,authority,cfg,name,intent,expiry,expected,exact,payment,system,clock,ctx)}
#[test_only]
public fun fulfill_for_testing<C>(work:&mut Work<C>,p:&mut Product<C>,authority:&Authority,a:&Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,definitions:vector<vector<u8>>,ctx:&mut TxContext){fulfill(work,p,authority,a,definitions,ctx)}
#[test_only]
public fun close_for_testing<C>(i:&Instance<C>,a:&mut Agreement<Product<C>,C,AgencyAuthority1,AgencyRevision1>,p:&Product<C>,authority:&Authority,cfg:&Config<C>,work:Work<C>,system:&System,clock:&Clock,ctx:&TxContext):ID{close(i,a,p,authority,cfg,work,system,clock,ctx)}
#[test_only]
public fun pause_for_testing<C>(p:&mut Product<C>,authority:&mut Authority){let version=maker::current_version(p);release::pause(p,&mut authority.control,version)}
