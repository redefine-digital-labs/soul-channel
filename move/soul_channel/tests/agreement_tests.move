#[test_only]
module soul_channel::agreement_tests;
use soul_channel::agreement::{Self as channel, Agreement, Instance, AdminCap};
use soul_channel::producer_fixture::{Self as producer, Product, Authority, Fulfilled, TestCoin};
use sui::coin;
use sui::balance;

const OWNER: address = @0xB;
const PRINCIPAL: address = @0xA;
const AGENT: address = @0xB;
const BENEFICIARY: address = @0xD;

fun context(sender: address, epoch: u64): TxContext { tx_context::new_from_hint(sender, (sender.to_bytes()[31] as u64) + epoch * 256, epoch, 0, 0) }
fun intent(n: u8): vector<u8> { vector::tabulate!(32, |_| n) }
fun start(cap: u64): (Instance<TestCoin>, AdminCap, Product, Agreement<Product,TestCoin,Authority,Fulfilled>) {
    let mut ctx = context(OWNER, 0);
    let (i, c) = channel::create(&mut ctx);
    let p = producer::create(PRINCIPAL, BENEFICIARY, cap, 900, &mut ctx);
    let a = channel::offer(&i, &c, &p, &p, 1, 0, PRINCIPAL, AGENT, BENEFICIARY,
        channel::issuance(), 3, 1000, 1000, 1, 5, &mut ctx);
    (i, c, p, a)
}
fun accept(i: &Instance<TestCoin>, a: &mut Agreement<Product,TestCoin,Authority,Fulfilled>, p: &Product) {
    let ctx = context(PRINCIPAL, 0);
    let exact = channel::commitment(a);
    producer::accept(i, a, p, exact, 0, &ctx)
}
fun execute(i: &mut Instance<TestCoin>, a: &mut Agreement<Product,TestCoin,Authority,Fulfilled>, p: &mut Product,
    n: u8, quantity: u64, generation: u64, gross: u64, ctx: &mut TxContext) {
    let payment = coin::mint_for_testing<TestCoin>(gross, ctx);
    let exact = channel::commitment(a);
    let (authorization, net) = producer::authorize(i, a, p, intent(n), quantity, generation, exact, payment, ctx);
    let fulfilled = producer::fulfill(p, intent(n), quantity, net, ctx);
    producer::complete(i, a, p, authorization, fulfilled, ctx)
}
fun cleanup(i: Instance<TestCoin>, c: AdminCap, p: Product, a: Agreement<Product,TestCoin,Authority,Fulfilled>) {
    channel::destroy_for_testing(a); producer::destroy(p);
    let value = channel::destroy_instance_for_testing(i, c); assert!(balance::destroy_for_testing(value) <= 300, 99)
}

#[test]
fun selected_channel_coin_split_and_quota() {
    let (mut i, c, mut p, mut a) = start(4); accept(&i, &mut a, &p);
    let mut ctx = context(AGENT, 1); execute(&mut i, &mut a, &mut p, 1, 2, 1, 2000, &mut ctx);
    assert!(channel::used(&a) == 2 && channel::completed(&a) == 2 && producer::supply(&p) == 2 && channel::income(&i) == 200, 99);
    let mut owner = context(OWNER, 1); channel::set_paused(&mut i, &c, true, &owner);
    assert!(coin::burn_for_testing(channel::withdraw(&mut i, &c, 200, &mut owner)) == 200, 99);
    cleanup(i, c, p, a)
}
#[test]
fun independent_instance_quotas_and_direct_path_do_not_duplicate_supply() {
    let (mut i, c, mut p, mut a) = start(3); accept(&i, &mut a, &p);
    let mut owner = context(OWNER, 1);
    let (mut other, cap) = channel::create<TestCoin>(&mut owner);
    assert!(object::id(&i) != object::id(&other),99);
    let mut b = channel::offer<Product,TestCoin,Authority,Fulfilled,Product>(&other, &cap, &p, &p, 1, 0, PRINCIPAL, AGENT, BENEFICIARY,
        channel::issuance(), 1, 1000, 1000, 1, 5, &mut owner); accept(&other, &mut b, &p);
    let mut ctx = context(AGENT, 1);
    // Direct producer path has no channel fee or channel quota mutation.
    let payment = coin::mint_for_testing<TestCoin>(900, &mut ctx);
    producer::direct(&mut p, 1, payment, &mut ctx);
    execute(&mut i, &mut a, &mut p, 1, 1, 1, 1000, &mut ctx);
    execute(&mut other, &mut b, &mut p, 2, 1, 1, 1000, &mut ctx);
    assert!(producer::supply(&p) == 3 && channel::used(&a) == 1 && channel::used(&b) == 1, 99);
    channel::destroy_for_testing(b); assert!(balance::destroy_for_testing(channel::destroy_instance_for_testing(other, cap)) == 100, 99);
    cleanup(i, c, p, a)
}
#[test]
fun suspend_reasons_and_safe_exit_recovery() {
    let (mut i, c, mut p, mut a) = start(4); accept(&i, &mut a, &p);
    channel::suspend(&mut a, 1, &context(PRINCIPAL,1)); channel::suspend(&mut a, 2, &context(AGENT,1));
    channel::resume(&mut a, 3, &context(PRINCIPAL,1)); assert!(channel::status(&a) == 4, 99);
    channel::resume(&mut a, 4, &context(AGENT,1)); assert!(channel::status(&a) == 1, 99);
    let mut agent = context(AGENT,1);
    execute(&mut i, &mut a, &mut p, 1, 1, 5, 1000, &mut agent);
    let mut owner = context(OWNER, 1); channel::set_paused(&mut i, &c, true, &owner);
    channel::revoke(&mut a, 5, &context(PRINCIPAL,1)); assert!(channel::status(&a) == 2, 99);
    let mut owner = context(OWNER,1);
    assert!(coin::burn_for_testing(channel::withdraw(&mut i, &c, 100, &mut owner)) == 100, 99);
    cleanup(i, c, p, a)
}
#[test]
fun expiry_permissionless_during_pause() {
    let (mut i, c, p, mut a) = start(4); accept(&i, &mut a, &p);
    let owner = context(OWNER, 1); channel::set_paused(&mut i, &c, true, &owner);
    channel::expire(&mut a, &context(@0xEEE, 5)); assert!(channel::status(&a) == 3, 99); cleanup(i, c, p, a)
}

#[test, expected_failure(abort_code=2, location=soul_channel::agreement)]
fun wrong_exact_consent_refused() {
    let (i, c, p, mut a) = start(4); producer::accept(&i, &mut a, &p, intent(0), 0, &context(PRINCIPAL,0)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=0, location=soul_channel::agreement)]
fun unauthorized_accept_refused() {
    let (i,c,p,mut a)=start(4); let exact=channel::commitment(&a);
    producer::accept(&i,&mut a,&p,exact,0,&context(AGENT,0)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=3, location=soul_channel::agreement)]
fun offered_has_no_authority() {
    let (mut i,c,mut p,mut a)=start(4); execute(&mut i,&mut a,&mut p,1,1,0,1000,&mut context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=0, location=soul_channel::agreement)]
fun unauthorized_agent_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut context(PRINCIPAL,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=4, location=soul_channel::agreement)]
fun stale_agreement_generation_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); execute(&mut i,&mut a,&mut p,1,1,0,1000,&mut context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=4, location=soul_channel::agreement)]
fun actual_source_generation_rotation_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); producer::rotate(&mut p);
    execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=5, location=soul_channel::agreement)]
fun before_start_epoch_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut context(AGENT,0)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=5, location=soul_channel::agreement)]
fun exact_expiry_boundary_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut context(AGENT,5)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=7, location=soul_channel::agreement)]
fun quota_exhaustion_refused() {
    let (mut i,c,mut p,mut a)=start(5); accept(&i,&mut a,&p); let mut ctx=context(AGENT,1);
    execute(&mut i,&mut a,&mut p,1,3,1,3000,&mut ctx); execute(&mut i,&mut a,&mut p,2,1,1,1000,&mut ctx); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=8, location=soul_channel::agreement)]
fun underpayment_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); execute(&mut i,&mut a,&mut p,1,1,1,999,&mut context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=8, location=soul_channel::agreement)]
fun overpayment_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); execute(&mut i,&mut a,&mut p,1,1,1,1001,&mut context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=9, location=soul_channel::agreement)]
fun repeated_intent_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); let mut ctx=context(AGENT,1);
    execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut ctx); execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut ctx); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=3, location=soul_channel::agreement)]
fun revoked_agreement_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); channel::revoke(&mut a,1,&context(PRINCIPAL,1));
    execute(&mut i,&mut a,&mut p,1,1,2,1000,&mut context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=3, location=soul_channel::agreement)]
fun revoked_cannot_resume() {
    let (i,c,p,mut a)=start(4); accept(&i,&mut a,&p); channel::revoke(&mut a,1,&context(PRINCIPAL,1));
    channel::resume(&mut a,2,&context(PRINCIPAL,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=3, location=soul_channel::agreement)]
fun expired_cannot_accept_again() {
    let (i,c,p,mut a)=start(4); channel::expire(&mut a,&context(AGENT,5));
    let exact=channel::commitment(&a); producer::accept(&i,&mut a,&p,exact,1,&context(PRINCIPAL,5)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=10, location=soul_channel::agreement)]
fun service_pause_blocks_new_risk() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); channel::set_paused(&mut i,&c,true,&context(OWNER,1));
    execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=100, location=soul_channel::producer_fixture)]
fun producer_total_supply_remains_authoritative() {
    let (mut i,c,mut p,mut a)=start(1); accept(&i,&mut a,&p); execute(&mut i,&mut a,&mut p,1,2,1,2000,&mut context(AGENT,1)); cleanup(i,c,p,a)
}

#[test, expected_failure(abort_code=6, location=soul_channel::agreement)]
fun same_type_wrong_source_instance_refused() {
    let (mut i,c,p,mut a)=start(4); accept(&i,&mut a,&p);
    let mut ctx=context(AGENT,1); let mut wrong=producer::create(PRINCIPAL,BENEFICIARY,4,900,&mut ctx);
    execute(&mut i,&mut a,&mut wrong,1,1,1,1000,&mut ctx); producer::destroy(wrong); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=1, location=soul_channel::agreement)]
fun wrong_service_instance_refused() {
    let (i,c,p,mut a)=start(4); let mut ctx=tx_context::new_from_hint(OWNER,999,0,0,0); let (wrong,cap)=channel::create<TestCoin>(&mut ctx);
    accept(&wrong,&mut a,&p); balance::destroy_for_testing(channel::destroy_instance_for_testing(wrong,cap)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=0, location=soul_channel::agreement)]
fun unauthorized_income_exit_refused() {
    let (mut i,c,p,a)=start(4); let mut ctx=context(PRINCIPAL,0);
    coin::burn_for_testing(channel::withdraw(&mut i,&c,0,&mut ctx)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=1, location=soul_channel::agreement)]
fun mismatched_admin_cap_refused() {
    let (mut i,c,p,a)=start(4); let mut ctx=tx_context::new_from_hint(OWNER,999,0,0,0); let (other,cap)=channel::create<TestCoin>(&mut ctx);
    channel::set_paused(&mut i,&cap,true,&ctx); balance::destroy_for_testing(channel::destroy_instance_for_testing(other,cap)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=3, location=soul_channel::agreement)]
fun revoke_between_authorize_and_complete_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); let mut ctx=context(AGENT,1);
    let exact=channel::commitment(&a); let pay=coin::mint_for_testing<TestCoin>(1000,&mut ctx);
    let (authorization,net)=producer::authorize(&mut i,&mut a,&p,intent(1),1,1,exact,pay,&mut ctx);
    let fulfilled=producer::fulfill(&mut p,intent(1),1,net,&mut ctx);
    channel::revoke(&mut a,1,&ctx); producer::complete(&i,&mut a,&p,authorization,fulfilled,&ctx); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=4, location=soul_channel::agreement)]
fun source_rotation_between_authorize_and_complete_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); let mut ctx=context(AGENT,1);
    let exact=channel::commitment(&a); let pay=coin::mint_for_testing<TestCoin>(1000,&mut ctx);
    let (authorization,net)=producer::authorize(&mut i,&mut a,&p,intent(1),1,1,exact,pay,&mut ctx);
    producer::rotate(&mut p); let fulfilled=producer::fulfill(&mut p,intent(1),1,net,&mut ctx);
    producer::complete(&i,&mut a,&p,authorization,fulfilled,&ctx); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=9, location=soul_channel::agreement)]
fun cross_intent_completion_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); let mut ctx=context(AGENT,1);
    let exact=channel::commitment(&a); let pay=coin::mint_for_testing<TestCoin>(1000,&mut ctx);
    let (authorization,net)=producer::authorize(&mut i,&mut a,&p,intent(1),1,1,exact,pay,&mut ctx);
    let fulfilled=producer::fulfill(&mut p,intent(2),1,net,&mut ctx);
    producer::complete(&i,&mut a,&p,authorization,fulfilled,&ctx); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=9, location=soul_channel::agreement)]
fun mismatched_beneficiary_completion_refused() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); let mut ctx=context(AGENT,1);
    let exact=channel::commitment(&a); let pay=coin::mint_for_testing<TestCoin>(1000,&mut ctx);
    let (authorization,net)=producer::authorize(&mut i,&mut a,&p,intent(1),1,1,exact,pay,&mut ctx);
    producer::wrong_beneficiary(&mut p); let fulfilled=producer::fulfill(&mut p,intent(1),1,net,&mut ctx);
    producer::complete(&i,&mut a,&p,authorization,fulfilled,&ctx); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=3, location=soul_channel::agreement)]
fun other_party_pause_reason_cannot_be_cleared() {
    let (i,c,p,mut a)=start(4); accept(&i,&mut a,&p);
    channel::suspend(&mut a,1,&context(PRINCIPAL,1)); channel::resume(&mut a,2,&context(AGENT,1)); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=4, location=soul_channel::agreement)]
fun service_handover_invalidates_old_consent() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p);
    channel::handover(&mut i,c,@0xE,&context(OWNER,1));
    execute(&mut i,&mut a,&mut p,1,1,1,1000,&mut context(AGENT,1));
    channel::share(i); channel::destroy_for_testing(a); producer::destroy(p)
}
#[test]
fun commission_floor_uses_actual_coin_at_small_boundary() {
    let mut owner=context(OWNER,0); let (mut i,c)=channel::create<TestCoin>(&mut owner);
    let mut p=producer::create(PRINCIPAL,BENEFICIARY,1,1,&mut owner);
    let mut a=channel::offer<Product,TestCoin,Authority,Fulfilled,Product>(&i,&c,&p, &p,1,0,PRINCIPAL,AGENT,BENEFICIARY,
        channel::issuance(),1,1,1,0,5,&mut owner); accept(&i,&mut a,&p);
    let mut agent=context(AGENT,1); execute(&mut i,&mut a,&mut p,1,1,1,1,&mut agent);
    assert!(channel::income(&i)==0 && producer::supply(&p)==1,99); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=0, location=soul_channel::agreement)]
fun primitive_authority_cannot_impersonate_source() {
    let (i,c,p,a)=start(4); let mut owner=context(OWNER,0);
    let bad=channel::offer<Product,TestCoin,bool,Fulfilled,Product>(&i,&c,&p, &p,1,0,PRINCIPAL,AGENT,BENEFICIARY,
        channel::issuance(),1,1000,1000,0,5,&mut owner); channel::destroy_for_testing(bad); cleanup(i,c,p,a)
}
public struct ForeignWitness has drop { sealed: bool }
#[test, expected_failure(abort_code=0, location=soul_channel::agreement)]
fun foreign_module_authority_cannot_impersonate_source() {
    let (i,c,p,a)=start(4); let mut owner=context(OWNER,0);
    let bad=channel::offer<Product,TestCoin,ForeignWitness,Fulfilled,Product>(&i,&c,&p, &p,1,0,PRINCIPAL,AGENT,BENEFICIARY,
        channel::issuance(),1,1000,1000,0,5,&mut owner); channel::destroy_for_testing(bad); cleanup(i,c,p,a)
}
#[test, expected_failure(abort_code=0, location=soul_channel::agreement)]
fun authority_witness_cannot_be_selected_as_completion_role() {
    let (i,c,p,a)=start(4); let mut owner=context(OWNER,0);
    let bad=channel::offer<Product,TestCoin,Authority,Authority,Product>(&i,&c,&p, &p,1,0,PRINCIPAL,AGENT,BENEFICIARY,
        channel::issuance(),1,1000,1000,0,5,&mut owner); channel::destroy_for_testing(bad); cleanup(i,c,p,a)
}
#[test]
fun ended_requires_fresh_offer_and_exact_new_consent() {
    let (mut i,c,mut p,mut a)=start(4); accept(&i,&mut a,&p); channel::revoke(&mut a,1,&context(PRINCIPAL,1));
    let mut owner=context(OWNER,1);
    let mut fresh=channel::offer<Product,TestCoin,Authority,Fulfilled,Product>(&i,&c,&p, &p,1,0,PRINCIPAL,AGENT,BENEFICIARY,
        channel::issuance(),1,1000,1000,1,5,&mut owner);
    assert!(object::id(&a)!=object::id(&fresh),99); accept(&i,&mut fresh,&p);
    execute(&mut i,&mut fresh,&mut p,1,1,1,1000,&mut context(AGENT,1));
    assert!(channel::status(&a)==2 && channel::used(&a)==0 && channel::completed(&fresh)==1,99);
    channel::destroy_for_testing(fresh); cleanup(i,c,p,a)
}

#[test,expected_failure(abort_code=4,location=soul_channel::agreement)]
fun R1_stale_consent_after_actual_rotation_refused(){
 let(i,c,mut p,mut a)=start(4);let exact=channel::commitment(&a);producer::rotate(&mut p);
 producer::accept(&i,&mut a,&p,exact,0,&context(PRINCIPAL,0));cleanup(i,c,p,a)
}
#[test,expected_failure(abort_code=4,location=soul_channel::agreement)]
fun R2_stale_fulfillment_after_actual_rotation_refused(){
 let(mut i,c,mut p,mut a)=start(4);accept(&i,&mut a,&p);let mut ctx=context(AGENT,1);
 let exact=channel::commitment(&a);let pay=coin::mint_for_testing<TestCoin>(1000,&mut ctx);
 let(ticket,net)=producer::authorize(&mut i,&mut a,&p,intent(1),1,1,exact,pay,&mut ctx);
 let fulfilled=producer::fulfill(&mut p,intent(1),1,net,&mut ctx);producer::rotate(&mut p);
 producer::complete(&i,&mut a,&p,ticket,fulfilled,&ctx);cleanup(i,c,p,a)
}
