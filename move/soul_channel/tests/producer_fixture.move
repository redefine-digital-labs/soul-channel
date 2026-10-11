/// Protocol exercise only: this is NOT the existing production Maker.
#[test_only]
module soul_channel::producer_fixture;
use soul_channel::agreement::{Self, Agreement, Instance, Authorization};
use sui::coin::{Self, Coin};

public struct TestCoin has drop {}
public struct Product has key {
    id: UID, principal: address, beneficiary: address,
    version: u64, generation: u64, supply: u64, cap: u64, net_per_unit: u64,
}
public struct Authority has drop { seal: bool }
public struct Fulfilled has drop { seal: bool }
public struct Item has key, store { id: UID, source: ID }

public fun create(principal: address, beneficiary: address, cap: u64, net_per_unit: u64, ctx: &mut TxContext): Product {
    Product { id: object::new(ctx), principal, beneficiary, version: 1, generation: 0, supply: 0, cap, net_per_unit }
}
public struct Completed {intent:vector<u8>,quantity:u64,beneficiary:address}
public fun accept(i:&Instance<TestCoin>,a:&mut Agreement<Product,TestCoin,Authority,Fulfilled>,p:&Product,exact:vector<u8>,expected:u64,ctx:&TxContext) {
 agreement::accept(i,a,p,p,p.version,p.generation,p.principal,Authority{seal:true},exact,expected,ctx)
}
public fun authorize(i:&mut Instance<TestCoin>,a:&mut Agreement<Product,TestCoin,Authority,Fulfilled>,p:&Product,intent:vector<u8>,quantity:u64,expected:u64,exact:vector<u8>,payment:Coin<TestCoin>,ctx:&mut TxContext):(Authorization<Product,TestCoin,Authority,Fulfilled>,Coin<TestCoin>) {
 agreement::authorize(i,a,p,p,p.version,p.generation,p.principal,Authority{seal:true},intent,quantity,expected,exact,payment,ctx)
}
public fun complete(i:&Instance<TestCoin>,a:&mut Agreement<Product,TestCoin,Authority,Fulfilled>,p:&Product,ticket:Authorization<Product,TestCoin,Authority,Fulfilled>,fulfilled:Completed,ctx:&TxContext){
 let Completed{intent,quantity,beneficiary}=fulfilled;
 agreement::complete(i,a,p,p,p.version,p.generation,p.principal,ticket,ctx.sender(),beneficiary,intent,quantity,agreement::issuance(),Fulfilled{seal:true},ctx)
}
fun manufacture(p: &mut Product, quantity: u64, payment: Coin<TestCoin>, ctx: &mut TxContext) {
    assert!(quantity > 0 && quantity <= p.cap - p.supply, 100);
    assert!(coin::value(&payment) == quantity * p.net_per_unit, 101);
    p.supply = p.supply + quantity;
    transfer::public_transfer(payment, p.beneficiary);
    let mut n = 0;
    while(n < quantity) {
        transfer::public_transfer(Item { id: object::new(ctx), source: object::id(p) }, ctx.sender()); n = n + 1
    };
}
public fun direct(p: &mut Product, quantity: u64, payment: Coin<TestCoin>, ctx: &mut TxContext) { manufacture(p, quantity, payment, ctx) }
public fun fulfill(p: &mut Product, intent: vector<u8>, quantity: u64, payment: Coin<TestCoin>, ctx: &mut TxContext): Completed {
    manufacture(p, quantity, payment, ctx);
    Completed{intent,quantity,beneficiary:p.beneficiary}
}
public fun supply(p: &Product): u64 { p.supply }
/// Test adversarial inputs, not public producer authority pathways.
public fun rotate(p: &mut Product) { p.generation = p.generation + 1 }
public fun wrong_beneficiary(p: &mut Product) { p.beneficiary = @0xBAD }
public fun destroy(p: Product) {
    let Product { id, principal:_, beneficiary:_, version:_, generation:_, supply:_, cap:_, net_per_unit:_ } = p; id.delete()
}
