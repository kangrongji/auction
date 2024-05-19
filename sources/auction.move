module auction::auction {

    //==============================================================================================
    // Dependencies
    //==============================================================================================

    use sui::balance::{Self, Balance};
    use sui::event::{Self};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use sui::errors::{assert, code, abort, UserError};
    use sui::types::address::{address};

    //==============================================================================================
    // Error codes
    //==============================================================================================

    // When auction has already ended.
    const EAuctionHasEnded: u64 = 0;
    // When auction is still going on.
    const EAuctionHasNotEnded: u64 = 1;
    // When the bidder provides fewer balance.
    const EBalanceNotEnough: u64 = 2;
    // When the auctioneer sets new price but higher than the present.
    const ENewPriceMustBeLower: u64 = 3;
    // When the auctioneer provides wrong cap.
    const EAuctionIDMismatch: u64 = 4;
    // Unauthorized action attempted.
    const EUnauthorized: u64 = 5;

    //==============================================================================================
    // Events
    //==============================================================================================

    // When a new auction is created.
    public struct AuctionCreated has copy, drop {
        auction_id: ID,
        maximal_price: u64,
    }

    // When a new price is set.
    public struct NewPriceSet has copy, drop {
        auction_id: ID,
        new_price: u64,
    }

    // When an auction is successfully ended.
    public struct AuctionSucceeded has copy, drop {
        auction_id: ID,
        final_price: u64,
        bidder_address: address,
    }

    // When an auction is stopped by the auctioneer.
    public struct AuctionStopped has copy, drop {
        auction_id: ID,
    }

    //==============================================================================================
    // Structs
    //==============================================================================================

    // The auction object
    public struct Auction<T0: store, phantom T1> has key {
        id: UID,
        item: Option<T0>,
        present_price: u64,
        has_ended: bool,
        proceed: Balance<T1>,
        auctioneer: address,
        min_bid: Option<u64>
    }

    // Capability of being the auctioneer
    public struct AuctionCap has key, store {
        id: UID,
        auction_id: ID,
    }

    //==============================================================================================
    // Getters
    //==============================================================================================

    // Get the present auction price
    public fun get_present_price<T0: store, T1>(auction: &Auction<T0, T1>): u64 {
        auction.present_price
    }

    //==============================================================================================
    // Public functions
    //==============================================================================================

    // Create a new auction
    public fun create<T0: store, T1>(
        item: T0, maximal_price: u64, min_bid: Option<u64>, ctx: &mut TxContext
    ): AuctionCap {
        let auction = Auction<T0, T1> {
            id: object::new(ctx),
            item: option::some(item),
            present_price: maximal_price,
            has_ended: false,
            proceed: balance::zero(),
            auctioneer: tx_context::sender(ctx),
            min_bid: min_bid,
        };
        let auction_cap = AuctionCap {
            id: object::new(ctx),
            auction_id: object::uid_to_inner(&auction.id),
        };
        event::emit(AuctionCreated {
            auction_id: object::uid_to_inner(&auction.id),
            maximal_price: auction.present_price,
        });
        transfer::share_object(auction);
        auction_cap
    }

    // The auctioneer could set a new auction price
    public fun set_price<T0: store, T1>(
        auction: &mut Auction<T0, T1>, auction_cap: &AuctionCap, new_price: u64, ctx: &mut TxContext
    ) {
        assert!(object::uid_to_inner(&auction.id) == auction_cap.auction_id, EAuctionIDMismatch);
        assert!(auction.auctioneer == tx_context::sender(ctx), EUnauthorized);
        assert!(!auction.has_ended, EAuctionHasEnded);
        assert!(new_price < auction.present_price, ENewPriceMustBeLower);
        auction.present_price = new_price;
        event::emit(NewPriceSet {
            auction_id: object::uid_to_inner(&auction.id),
            new_price: auction.present_price,
        });
    }

    // Anyone could bid the price and get the auction item (if succeeded)
    public fun bid<T0: store, T1>(
        auction: &mut Auction<T0, T1>, mut bid_balance: Balance<T1>, ctx: &mut TxContext
    ): (T0, Balance<T1>) {
        assert!(!auction.has_ended, EAuctionHasEnded);
        assert!(bid_balance.value() >= auction.present_price, EBalanceNotEnough);
        if (option::is_some(&auction.min_bid)) {
            let min_bid = option::borrow(&auction.min_bid).unwrap();
            assert!(bid_balance.value() >= min_bid, EBalanceNotEnough);
        }
        let proceed = balance::split(&mut bid_balance, auction.present_price);
        balance::join(&mut auction.proceed, proceed);
        auction.has_ended = true;
        let item = option::extract(&mut auction.item);
        event::emit(AuctionSucceeded {
            auction_id: object::uid_to_inner(&auction.id),
            final_price: auction.present_price,
            bidder_address: ctx.sender(),
        });
        (item, bid_balance)
    }

    // The auctioneer could claim the proceeds after the auction is successfully ended
    public fun claim<T0: store, T1>(
        auction: Auction<T0, T1>, auction_cap: AuctionCap, ctx: &mut TxContext
    ): Balance<T1> {
        assert!(object::uid_to_inner(&auction.id) == auction_cap.auction_id, EAuctionIDMismatch);
        assert!(auction.auctioneer == tx_context::sender(ctx), EUnauthorized);
        assert!(auction.has_ended, EAuctionHasNotEnded);
        let Auction { id, item, present_price: _, has_ended: _, proceed, auctioneer: _, min_bid: _ } = auction;
        object::delete(id);
        option::destroy_none(item);
        let AuctionCap { id, auction_id: _ } = auction_cap;
        object::delete(id);
        proceed
    }

    // The auctioneer could stop the auction before the auction is ended
    public fun stop<T0: store, T1>(
        auction: Auction<T0, T1>, auction_cap: AuctionCap, ctx: &mut TxContext
    ): T0 {
        assert!(object::uid_to_inner(&auction.id) == auction_cap.auction_id, EAuctionIDMismatch);
        assert!(auction.auctioneer == tx_context::sender(ctx), EUnauthorized);
        assert!(!auction.has_ended, EAuctionHasEnded);
        let Auction { id, item, present_price: _, has_ended: _, proceed, auctioneer: _, min_bid: _ } = auction;
        event::emit(AuctionStopped {
            auction_id: object::uid_to_inner(&id),
        });
        object::delete(id);
        balance::destroy_zero(proceed);
        let item = option::destroy_some(item);
        let AuctionCap { id, auction_id: _ } = auction_cap;
        object::delete(id);
        item
    }

    //==============================================================================================
    // Utility functions
    //==============================================================================================

    // Verify ownership of the auction cap
    fun verify_auction_ownership(auction: &Auction, auction_cap: &AuctionCap) -> bool {
        object::uid_to_inner(&auction.id) == auction_cap.auction_id
    }

    // Optional: Implement timeout management for auction (placeholder)
    public fun set_auction_timeout(auction_id: ID, timeout_duration: u64, ctx: &mut TxContext) {
        // Implement timeout logic based on your requirements
        // Placeholder logic; implement according to your system's needs
        event::emit(&"AuctionTimeoutSet", &(auction_id, timeout_duration));
    }

    // Optional: Review Transfer Policies to ensure security (placeholder)
    public fun review_transfer_policy<T: store>(policy: &TransferPolicy<T>) -> bool {
        // Implement logic to check policy's constraints
        // Ensure it prevents unauthorized access or manipulation
        // Placeholder logic; replace with actual checks
        true
    }
}
