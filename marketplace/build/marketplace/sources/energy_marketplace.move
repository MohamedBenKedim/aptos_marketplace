module DOV::energy_marketplace {
    use std::signer;
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_std::event::{Self, EventHandle};    
    use aptos_std::table::{Self, Table};
    use DOV::dov_token;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset;


    const ESELLER_CAN_NOT_BE_BUYER: u64 = 1;
    const EINSUFFICIENT_QUANTITY: u64 = 2;
    const EINVALID_PRICE: u64 = 3;

    struct MarketId has store, drop, copy {
        market_name: String,
        market_address: address,
    }

    struct EnergyAsset has store, drop, copy {
        market_id: MarketId,
        name: String,
        price: u64,
        quantity: u64,
        seller: address,
    }

    struct Market has key {
        market_id: MarketId,
        assets: Table<u64, EnergyAsset>,
        next_asset_id: u64,
    }

    struct MarketEvents has key {
        list_asset_events: EventHandle<ListAssetEvent>,
        buy_asset_events: EventHandle<BuyAssetEvent>,
    }

    struct ListAssetEvent has drop, store {
        asset_id: u64,
        market_id: MarketId,
        seller: address,
        name: String,
        price: u64,
        quantity: u64,
        timestamp: u64,
    }

    struct BuyAssetEvent has drop, store {
        asset_id: u64,
        market_id: MarketId,
        buyer: address,
        seller: address,
        name: String,
        price: u64,
        quantity: u64,
        timestamp: u64,
    }

    public fun initialize_market(account: &signer, market_name: String) {
        let account_addr = signer::address_of(account);
        let market_id = MarketId { market_name, market_address: account_addr };
        
        if (!exists<Market>(account_addr)) {
            move_to(account, Market {
                market_id,
                assets: table::new(),
                next_asset_id: 0,
            });
        };

        if (!exists<MarketEvents>(account_addr)) {
            move_to(account, MarketEvents {
                list_asset_events: account::new_event_handle<ListAssetEvent>(account),
                buy_asset_events: account::new_event_handle<BuyAssetEvent>(account),
            });
        };
    }

    public entry fun list_energy_asset(
        seller: &signer,
        market_address: address,
        market_name: String,
        asset_name: String,
        price: u64,
        quantity: u64
    ) acquires Market, MarketEvents {
        assert!(price > 0, EINVALID_PRICE);
        assert!(quantity > 0, EINSUFFICIENT_QUANTITY);

        let seller_addr = signer::address_of(seller);
        let market = borrow_global_mut<Market>(market_address);
        let market_id = MarketId { market_name, market_address };
        
        let asset_id = market.next_asset_id;
        market.next_asset_id = market.next_asset_id + 1;

        let asset = EnergyAsset {
            market_id,
            name: asset_name,
            price,
            quantity,
            seller: seller_addr,
        };

        table::add(&mut market.assets, asset_id, asset);

        // Mint DOV tokens to the seller
        let dov_amount = quantity * price;
        dov_token::mint(seller, seller_addr, dov_amount);

        // Emit event
        let events = borrow_global_mut<MarketEvents>(market_address);
        event::emit_event(&mut events.list_asset_events, ListAssetEvent {
            asset_id,
            market_id,
            seller: seller_addr,
            name: asset_name,
            price,
            quantity,
            timestamp: timestamp::now_microseconds(),
        });
    }

   public entry fun buy_energy_asset(
    buyer: &signer,
    market_address: address,
    market_name: String,
    asset_id: u64,
    quantity_to_buy: u64
) acquires Market, MarketEvents {
    let buyer_addr = signer::address_of(buyer);
    let market = borrow_global_mut<Market>(market_address);
    let market_id = MarketId { market_name, market_address };
    
    let asset = table::borrow_mut(&mut market.assets, asset_id);
    assert!(asset.seller != buyer_addr, ESELLER_CAN_NOT_BE_BUYER);
    assert!(asset.quantity >= quantity_to_buy, EINSUFFICIENT_QUANTITY);

    let total_price = quantity_to_buy * asset.price;
    let seller = asset.seller;
    let asset_name = asset.name;
    let asset_price = asset.price;
    
    // Transfer DOV tokens from buyer to seller using dov_token::transfer
    dov_token::transfer(buyer, buyer_addr, seller, total_price);

    // Update asset quantity
    asset.quantity = asset.quantity - quantity_to_buy;
    
    let should_remove = asset.quantity == 0;

    // Emit event
    let events = borrow_global_mut<MarketEvents>(market_address);
    event::emit_event(&mut events.buy_asset_events, BuyAssetEvent {
        asset_id,
        market_id,
        buyer: buyer_addr,
        seller,
        name: asset_name,
        price: asset_price,
        quantity: quantity_to_buy,
        timestamp: timestamp::now_microseconds(),
    });

    // Remove asset if all energy is sold
    if (should_remove) {
        table::remove(&mut market.assets, asset_id);
    };
}
    #[view]
    public fun get_asset(market_address: address, asset_id: u64): (String, u64, u64, address) acquires Market {
        let market = borrow_global<Market>(market_address);
        let asset = table::borrow(&market.assets, asset_id);
        (asset.name, asset.price, asset.quantity, asset.seller)
    }
}