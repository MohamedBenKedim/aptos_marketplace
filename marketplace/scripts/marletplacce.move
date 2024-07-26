module DOV::EnergyMarketplace {
    use std::signer;
    use std::vector;
    use aptos_framework::object::{Self, ConstructorRef, Object};
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use DOV::dov_token;

    /// Errors
    const ERROR_LISTING_NOT_FOUND: u64 = 1;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 2;
    const ERROR_UNAUTHORIZED: u64 = 3;
    const ERROR_INVALID_AMOUNT: u64 = 4;

    /// Struct to represent an energy listing
    struct EnergyListing has key {
        energy_amount: u64,
        price_per_unit: u64,
        description: vector<u8>,
        owner: address,
    }

    /// Resource to store all listings
    struct Marketplace has key {
        listings: vector<Object<EnergyListing>>,
    }

    /// Initialize the marketplace
    fun init_module(admin: &signer) {
        move_to(admin, Marketplace { listings: vector::empty() });
    }

    public entry fun initialize_marketplace(admin: &signer) {
    if (!exists<Marketplace>(@DOV)) {
        move_to(admin, Marketplace { listings: vector::empty() });
    }
}

    /// List energy for sale
    public entry fun list_energy(
        account: &signer,
        energy_amount: u64,
        price_per_unit: u64,
        description: vector<u8>
    ) acquires Marketplace {
        let owner = signer::address_of(account);
        
        // Mint tokens to represent the energy
        dov_token::mint(account, owner, energy_amount);

        let constructor_ref = object::create_object(owner);
        let listing = EnergyListing {
            energy_amount,
            price_per_unit,
            description,
            owner,
        };
        let listing_obj = object::object_from_constructor_ref(&constructor_ref);
        move_to(&object::generate_signer(&constructor_ref), listing);

        let marketplace = borrow_global_mut<Marketplace>(@DOV);
        vector::push_back(&mut marketplace.listings, listing_obj);
    }


    /// Buy energy from a listing
    public entry fun buy_energy(
        buyer: &signer,
        listing_index: u64,
        amount_to_buy: u64
    ) acquires Marketplace, EnergyListing {
        let marketplace = borrow_global_mut<Marketplace>(@DOV);
        assert!(listing_index < vector::length(&marketplace.listings), ERROR_LISTING_NOT_FOUND);

        let listing_obj = vector::borrow(&marketplace.listings, listing_index);
        let listing = borrow_global_mut<EnergyListing>(object::object_address(listing_obj));

        assert!(amount_to_buy <= listing.energy_amount, ERROR_INVALID_AMOUNT);

        let total_price = amount_to_buy * listing.price_per_unit;
        let buyer_address = signer::address_of(buyer);

        // Transfer tokens from buyer to seller
        dov_token::transfer(buyer, buyer_address, listing.owner, total_price);

        // Update the listing
        listing.energy_amount = listing.energy_amount - amount_to_buy;

        // Remove the listing if all energy is sold
        if (listing.energy_amount == 0) {
            let removed_listing = vector::remove(&mut marketplace.listings, listing_index);
            let EnergyListing { energy_amount: _, price_per_unit: _, description: _, owner: _ } = move_from(object::object_address(&removed_listing));
        }
    }

    /// Remove a listing
    public entry fun remove_listing(owner: &signer, listing_index: u64) acquires Marketplace, EnergyListing {
        let marketplace = borrow_global_mut<Marketplace>(@DOV);
        assert!(listing_index < vector::length(&marketplace.listings), ERROR_LISTING_NOT_FOUND);

        let listing_obj = vector::borrow(&marketplace.listings, listing_index);
        let listing = borrow_global<EnergyListing>(object::object_address(listing_obj));

        assert!(listing.owner == signer::address_of(owner), ERROR_UNAUTHORIZED);

        let removed_listing = vector::remove(&mut marketplace.listings, listing_index);
        let EnergyListing { energy_amount: _, price_per_unit: _, description: _, owner: _ } = move_from(object::object_address(&removed_listing));
    }  

    struct ListingInfo has copy, drop {
    energy_amount: u64,
    price_per_unit: u64,
    description: vector<u8>,
    owner: address,
}

    /// Get all listings
   #[view]
    public fun get_all_listings(): vector<ListingInfo> acquires Marketplace, EnergyListing {
    let marketplace = borrow_global<Marketplace>(@DOV);
    let listings = vector::empty();

    let i = 0;
    let len = vector::length(&marketplace.listings);
    while (i < len) {
        let listing_obj = vector::borrow(&marketplace.listings, i);
        let listing = borrow_global<EnergyListing>(object::object_address(listing_obj));
        vector::push_back(&mut listings, ListingInfo {
            energy_amount: listing.energy_amount,
            price_per_unit: listing.price_per_unit,
            description: listing.description,
            owner: listing.owner,
        });
        i = i + 1;
    };

    listings
}

    /// Get a specific listing
    #[view]
    public fun get_listing(listing_index: u64): (u64, u64, vector<u8>, address) acquires Marketplace, EnergyListing {
        let marketplace = borrow_global<Marketplace>(@DOV);
        assert!(listing_index < vector::length(&marketplace.listings), ERROR_LISTING_NOT_FOUND);

        let listing_obj = vector::borrow(&marketplace.listings, listing_index);
        let listing = borrow_global<EnergyListing>(object::object_address(listing_obj));
        (listing.energy_amount, listing.price_per_unit, listing.description, listing.owner)
    }
}