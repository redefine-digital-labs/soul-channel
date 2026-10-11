/// Channel owns consent, lifecycle, selected quota and funded service income.
/// Authority/business checks are implemented by the exact reviewed producer
/// adapter selected by principal consent. No public snapshot/completion issuer.
module soul_channel::agreement;

use std::bcs;
use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use std::hash;
use sui::table::{Self, Table};

const EAuthority: u64 = 0;
const EInstance: u64 = 1;
const ETerms: u64 = 2;
const EState: u64 = 3;
const EGeneration: u64 = 4;
const EExpired: u64 = 5;
const ESource: u64 = 6;
const EQuota: u64 = 7;
const EPayment: u64 = 8;
const EIntent: u64 = 9;
const EPaused: u64 = 10;
const EVersion: u64 = 11;
const REVISION: u64 = 2;
const OFFERED: u8 = 0;
const ACCEPTED: u8 = 1;
const REVOKED: u8 = 2;
const EXPIRED: u8 = 3;
const SUSPENDED: u8 = 4;

public enum Action has copy, drop, store { Issuance, Market }
public fun issuance(): Action { Action::Issuance }
public fun market(): Action { Action::Market }

public struct Instance<phantom C> has key {
    id: UID,
    revision: u64,
    owner: address,
    generation: u64,
    paused: bool,
    income: Balance<C>,
}
/// No store: only the defining handover function transfers this capability.
public struct AdminCap has key { id: UID, instance: ID }

public struct Terms has copy, drop, store {
    domain: vector<u8>, instance: ID, instance_generation: u64,
    source: ID, source_type: TypeName, coin_type: TypeName, control: ID, control_type: TypeName,
    authority_type: TypeName, completion_type: TypeName,
    source_version: u64, source_generation: u64,
    principal: address, agent: address, beneficiary: address,
    action: Action, quota: u64, gross_per_unit: u64, commission_bps: u16,
    starts_epoch: u64, expires_epoch: u64,
}
public struct Agreement<phantom S, phantom C, phantom A, phantom R> has key {
    id: UID, revision: u64, terms: Terms, commitment: vector<u8>,
    generation: u64, state: u8, reasons: u8, used: u64, completed: u64, intents: Table<vector<u8>, bool>,
}

/// Linear transaction obligation: cannot be dropped, copied or stored.
public struct Authorization<phantom S, phantom C, phantom A, phantom R> {
    instance: ID, instance_generation: u64, agreement: ID,
    generation: u64, terms: vector<u8>, actor: address,
    intent: vector<u8>, quantity: u64, expires_epoch: u64,
}
/// Historical event is query evidence, never an authorization.
public struct Settled has copy, drop {
    instance: ID, agreement: ID, generation: u64, intent: vector<u8>,
    actor: address, quantity: u64, commission: u64, producer_payment: u64,
}

public fun create<C>(ctx: &mut TxContext): (Instance<C>, AdminCap) {
    let i = Instance { id: object::new(ctx), revision: REVISION,
        owner: ctx.sender(), generation: 0, paused: false, income: balance::zero() };
    let cap = AdminCap { id: object::new(ctx), instance: object::id(&i) };
    (i, cap)
}
public fun share<C>(i: Instance<C>) { transfer::share_object(i) }
public fun deliver_admin(cap: AdminCap, ctx: &TxContext) { transfer::transfer(cap, ctx.sender()) }
public fun share_agreement<S,C,A,R>(a: Agreement<S,C,A,R>) { transfer::share_object(a) }
fun current<C>(i: &Instance<C>) { assert!(i.revision == REVISION, EVersion) }
fun admin<C>(i: &Instance<C>, c: &AdminCap, ctx: &TxContext) {
    current(i); assert!(c.instance == object::id(i), EInstance);
    assert!(i.owner == ctx.sender(), EAuthority)
}
public fun set_paused<C>(i: &mut Instance<C>, cap: &AdminCap, paused: bool, ctx: &TxContext) {
    admin(i, cap, ctx); i.paused = paused
}
/// Old agreements cannot act in a successor service authority generation.
public fun handover<C>(i: &mut Instance<C>, cap: AdminCap, next: address, ctx: &TxContext) {
    admin(i, &cap, ctx); assert!(next != i.owner, EAuthority);
    i.generation = i.generation + 1; i.owner = next;
    transfer::transfer(cap, next)
}
/// Service income exit remains available while paused or agreements terminal.
public fun withdraw<C>(i: &mut Instance<C>, cap: &AdminCap, amount: u64, ctx: &mut TxContext): Coin<C> {
    admin(i, cap, ctx); coin::from_balance(i.income.split(amount), ctx)
}

/// The exact independently owned adapter is consented in Terms. Nominal typing
/// does not prove its implementation: selected adapters must keep A/R private,
/// construct them inline only after live producer checks, and never return them.
fun issuer<A,R>() {
    let a = type_name::with_original_ids<A>(); let r = type_name::with_original_ids<R>();
    assert!(!a.is_primitive() && !r.is_primitive() && a != r, EAuthority);
    assert!(a.address_string() == r.address_string() && a.module_string() == r.module_string(), EAuthority)
}
public fun offer<S:key,C,A,R,K:key>(i: &Instance<C>, cap: &AdminCap, source: &S, control: &K,
    source_version: u64, source_generation: u64, principal: address, agent: address, beneficiary: address,
    action: Action, quota: u64, gross_per_unit: u64, commission_bps: u16,
    starts_epoch: u64, expires_epoch: u64, ctx: &mut TxContext): Agreement<S,C,A,R> {
    admin(i, cap, ctx); assert!(!i.paused, EPaused); assert!(agent == i.owner, EAuthority);
    assert!(commission_bps <= 10000 && quota > 0 && expires_epoch > starts_epoch && expires_epoch > ctx.epoch(), ETerms);
    issuer<A,R>();
    let terms = Terms { domain: b"soul-channel/agreement/v2", instance: object::id(i), instance_generation: i.generation,
        source: object::id(source), control: object::id(control), control_type: type_name::with_defining_ids<K>(), source_type: type_name::with_defining_ids<S>(), coin_type: type_name::with_defining_ids<C>(),
        authority_type: type_name::with_defining_ids<A>(), completion_type: type_name::with_defining_ids<R>(),
        source_version, source_generation, principal, agent, beneficiary, action, quota, gross_per_unit, commission_bps,
        starts_epoch, expires_epoch };
    let commitment = hash::sha2_256(bcs::to_bytes(&terms));
    Agreement { id: object::new(ctx), revision: REVISION, terms, commitment, generation: 0,
        state: OFFERED, reasons: 0, used: 0, completed: 0, intents: table::new(ctx) }
}
fun bind<S,C,A,R>(i: &Instance<C>, a: &Agreement<S,C,A,R>) {
    current(i); assert!(a.revision == REVISION, EVersion);
    assert!(a.terms.instance == object::id(i), EInstance);
    assert!(a.terms.instance_generation == i.generation, EGeneration)
}
fun source_matches<S:key,C,A,R,K:key>(a: &Agreement<S,C,A,R>, source: &S, control: &K,
    version: u64, generation: u64, principal: address) {
    assert!(object::id(source) == a.terms.source, ESource);
    assert!(object::id(control) == a.terms.control && type_name::with_defining_ids<K>() == a.terms.control_type, EAuthority);
    assert!(version == a.terms.source_version && generation == a.terms.source_generation, EGeneration);
    assert!(principal == a.terms.principal, EAuthority);
    assert!(type_name::with_defining_ids<A>() == a.terms.authority_type && type_name::with_defining_ids<R>() == a.terms.completion_type, EAuthority)
}
/// Call only inside the selected private adapter's live authority continuation.
public fun accept<S:key,C,A:drop,R,K:key>(i: &Instance<C>, a: &mut Agreement<S,C,A,R>, source: &S, control: &K,
    version: u64, source_generation: u64, principal: address, witness: A,
    exact_terms: vector<u8>, expected_generation: u64, ctx: &TxContext) {
    let _ = witness; bind(i, a); assert!(!i.paused, EPaused);
    assert!(ctx.sender() == a.terms.principal, EAuthority);
    assert!(a.state == OFFERED, EState); assert!(a.generation == expected_generation, EGeneration);
    assert!(a.commitment == exact_terms, ETerms); assert!(ctx.epoch() < a.terms.expires_epoch, EExpired);
    source_matches(a, source, control, version, source_generation, principal); a.state = ACCEPTED; a.generation = a.generation + 1
}
fun party<S,C,A,R>(a: &Agreement<S,C,A,R>, ctx: &TxContext): u8 {
    assert!(a.revision == REVISION, EVersion);
    if(ctx.sender() == a.terms.principal) 1
    else { assert!(ctx.sender() == a.terms.agent, EAuthority); 2 }
}
/// Either consenting party can end future agency; no refunds or rights erased.
public fun revoke<S,C,A,R>(a: &mut Agreement<S,C,A,R>, expected_generation: u64, ctx: &TxContext) {
    let _ = party(a, ctx); assert!(a.generation == expected_generation, EGeneration);
    assert!(a.state == OFFERED || a.state == ACCEPTED || a.state == SUSPENDED, EState);
    a.state = REVOKED; a.generation = a.generation + 1
}
/// Each party clears only its own reason. A terminal agreement never resumes.
public fun suspend<S,C,A,R>(a: &mut Agreement<S,C,A,R>, expected_generation: u64, ctx: &TxContext) {
    let bit = party(a, ctx); assert!(a.generation == expected_generation, EGeneration);
    assert!(a.state == ACCEPTED || a.state == SUSPENDED, EState);
    assert!(a.reasons & bit == 0, EState); a.reasons = a.reasons | bit;
    a.state = SUSPENDED; a.generation = a.generation + 1
}
public fun resume<S,C,A,R>(a: &mut Agreement<S,C,A,R>, expected_generation: u64, ctx: &TxContext) {
    let bit = party(a, ctx); assert!(a.generation == expected_generation, EGeneration);
    assert!(a.state == SUSPENDED && a.reasons & bit != 0, EState);
    assert!(ctx.epoch() < a.terms.expires_epoch, EExpired);
    a.reasons = a.reasons ^ bit; if(a.reasons == 0) a.state = ACCEPTED;
    a.generation = a.generation + 1
}
/// Expiry can be materialized by anyone, including during service pause.
public fun expire<S,C,A,R>(a: &mut Agreement<S,C,A,R>, ctx: &TxContext) {
    assert!(a.revision == REVISION, EVersion);
    assert!(ctx.epoch() >= a.terms.expires_epoch, EExpired);
    assert!(a.state != REVOKED && a.state != EXPIRED, EState);
    a.state = EXPIRED; a.generation = a.generation + 1
}
fun active<S,C,A,R>(i: &Instance<C>, a: &Agreement<S,C,A,R>, generation: u64, ctx: &TxContext) {
    bind(i, a); assert!(!i.paused, EPaused); assert!(a.state == ACCEPTED, EState);
    assert!(a.generation == generation, EGeneration); assert!(ctx.sender() == a.terms.agent, EAuthority);
    assert!(ctx.epoch() >= a.terms.starts_epoch && ctx.epoch() < a.terms.expires_epoch, EExpired)
}
/// Genuine Coin split, not quote-as-payment. The producer receives the remainder
/// in the same transaction and must close its own actual business obligation.
public fun authorize<S:key,C,A:drop,R,K:key>(i: &mut Instance<C>, a: &mut Agreement<S,C,A,R>, source: &S,
    control: &K, version: u64, source_generation: u64, principal: address, witness: A, intent: vector<u8>, quantity: u64, expected_generation: u64,
    exact_terms: vector<u8>, payment: Coin<C>, ctx: &mut TxContext): (Authorization<S,C,A,R>, Coin<C>) {
    active(i, a, expected_generation, ctx); assert!(a.commitment == exact_terms, ETerms);
    let _ = witness; source_matches(a, source, control, version, source_generation, principal); assert!(intent.length() == 32 && !a.intents.contains(intent), EIntent);
    assert!(quantity > 0 && quantity <= a.terms.quota - a.used, EQuota);
    let gross128 = (a.terms.gross_per_unit as u128) * (quantity as u128);
    assert!(gross128 <= 18446744073709551615u128, EPayment);
    let gross = (gross128 as u64); assert!(coin::value(&payment) == gross, EPayment);
    let commission = ((gross128 * (a.terms.commission_bps as u128) / 10000) as u64);
    let mut balance = coin::into_balance(payment); i.income.join(balance.split(commission));
    let net = coin::from_balance(balance, ctx); a.used = a.used + quantity; a.intents.add(intent, true);
    sui::event::emit(Settled { instance: object::id(i), agreement: object::id(a), generation: a.generation,
        intent, actor: ctx.sender(), quantity, commission, producer_payment: gross - commission });
    (Authorization { instance: object::id(i), instance_generation: i.generation, agreement: object::id(a),
        generation: a.generation, terms: a.commitment, actor: ctx.sender(), intent, quantity,
        expires_epoch: a.terms.expires_epoch }, net)
}
/// Rechecked after the producer's final operation, including same-PTB revoke.
public fun complete<S:key,C,A,R:drop,K:key>(i: &Instance<C>, a: &mut Agreement<S,C,A,R>, source: &S, control: &K,
    version: u64, source_generation: u64, principal: address, authorization: Authorization<S,C,A,R>,
    c_actor: address, c_beneficiary: address, c_intent: vector<u8>, c_quantity: u64, action: Action, witness: R, ctx: &TxContext) {
    let _ = witness;
    let Authorization { instance, instance_generation, agreement, generation, terms, actor, intent, quantity, expires_epoch } = authorization;
    active(i, a, generation, ctx);
    assert!(instance == object::id(i) && agreement == object::id(a), EInstance);
    assert!(instance_generation == i.generation, EGeneration);
    assert!(terms == a.commitment && actor == ctx.sender(), ETerms);
    assert!(ctx.epoch() < expires_epoch, EExpired);
    source_matches(a, source, control, version, source_generation, principal);
    assert!(c_actor == actor && c_beneficiary == a.terms.beneficiary && c_intent == intent && c_quantity == quantity && action == a.terms.action, EIntent);
    a.completed = a.completed + quantity
}

public fun commitment<S,C,A,R>(a: &Agreement<S,C,A,R>): vector<u8> { a.commitment }
public fun terms<S,C,A,R>(a: &Agreement<S,C,A,R>): &Terms { &a.terms }
public fun generation<S,C,A,R>(a: &Agreement<S,C,A,R>): u64 { a.generation }
public fun status<S,C,A,R>(a: &Agreement<S,C,A,R>): u8 { a.state }
public fun used<S,C,A,R>(a: &Agreement<S,C,A,R>): u64 { a.used }
public fun completed<S,C,A,R>(a: &Agreement<S,C,A,R>): u64 { a.completed }
public fun beneficiary(t: &Terms): address { t.beneficiary }
public fun action(t: &Terms): Action { t.action }
public fun income<C>(i: &Instance<C>): u64 { balance::value(&i.income) }

#[test_only]
public fun destroy_for_testing<S,C,A,R>(a: Agreement<S,C,A,R>) {
    let Agreement { id, revision:_, terms:_, commitment:_, generation:_, state:_, reasons:_, used:_, completed:_, intents } = a; table::drop(intents); id.delete()
}
#[test_only]
public fun destroy_instance_for_testing<C>(i: Instance<C>, cap: AdminCap): Balance<C> {
    let Instance { id, revision:_, owner:_, generation:_, paused:_, income } = i; id.delete();
    let AdminCap { id, instance:_ } = cap; id.delete(); income
}

public fun source_version(t:&Terms):u64{t.source_version}
public fun source_generation(t:&Terms):u64{t.source_generation}
public fun principal(t:&Terms):address{t.principal}
public fun control(t:&Terms):ID{t.control}
