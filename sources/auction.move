/*

    - Any user can initiate a new auction and assume the role of the auctioneer.
    - All users can participate as legitimate bidders.
    - The auctioneer continuously reduces the price from an initial maximum set at the start of the auction.
    - When the price drops to an acceptable level, the bidders can pay that price to obtain the auction item.
    - After the sale, the auctioneer can claim the auction proceeds.
    - The auctioneer retains the ability to stop the auction at any time.

*/
module auction::auction {

    //==============================================================================================
    // Dependencies
    //==============================================================================================

    use sui::balance::{Self, Balance};
    use sui::event::{Self};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::option;
    use sui::assert;

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
    public struct Auction<T0: store, T1> has key {
        id: UID,
        item: Option<T0>,
        present_price: u64,
        has_ended: bool,
        proceed: Balance<T1>
    }

    // Capability of being the auctioneer
    public struct AuctionCap has key, store {
        id: UID,
        auction_id: ID
    }

    //==============================================================================================
    // Getters
    //==============================================================================================

    // Get the present auction price
    public fun get_present_price<T0: store, T1> (auction: &Auction<T0, T1>): u64 {
        auction.present_price
    }

    // Get auction status
    public fun has_auction_ended<T0: store, T1>(auction: &Auction<T0, T1>): bool {
        auction.has_ended
    }

    //==============================================================================================
    // Public functions
    //==============================================================================================

    // Create a new auction
    public fun create<T0: store, T1> (item: T0, maximal_price: u64, ctx: &mut TxContext): (Auction<T0, T1>, AuctionCap) {
        let auction = Auction<T0, T1> {
            id: object::new(ctx),
            item: option::some(item),
            present_price: maximal_price,
            has_ended: false,
            proceed: balance::zero()
        };
        let auction_cap = AuctionCap {
            id: object::new(ctx),
            auction_id: object::uid_to_inner(&auction.id)
        };
        event::emit(AuctionCreated {
            auction_id: object::uid_to_inner(&auction.id),
            maximal_price: auction.present_price
        });
        (auction, auction_cap)
    }

    // The auctioneer could set a new auction price
    public fun set_price<T0: store, T1> (auction: &mut Auction<T0, T1>, auction_cap: &AuctionCap, new_price: u64) {
        assert!(object::uid_to_inner(&auction.id) == auction_cap.auction_id, EAuctionIDMismatch);
        assert!(!auction.has_ended, EAuctionHasEnded);
        assert!(new_price < auction.present_price, ENewPriceMustBeLower);
        auction.present_price = new_price;
        event::emit(NewPriceSet {
            auction_id: object::uid_to_inner(&auction.id),
            new_price: auction.present_price
        });
    }

    // Anyone could bid the price and get the auction item (if succeeded)
    public fun bid<T0: store, T1> (auction: &mut Auction<T0, T1>, mut bid_balance: Balance<T1>, ctx: &mut TxContext): (T0, Balance<T1>) {
        assert!(!auction.has_ended, EAuctionHasEnded);
        assert!(bid_balance.value() >= auction.present_price, EBalanceNotEnough);
        let proceed = balance::split(&mut bid_balance, auction.present_price);
        balance::join(&mut auction.proceed, proceed);
        auction.has_ended = true;
        let item = option::extract(&mut auction.item);
        event::emit(AuctionSucceeded {
            auction_id: object::uid_to_inner(&auction.id),
            final_price: auction.present_price,
            bidder_address: tx_context::sender(ctx)
        });
        (item, bid_balance)
    }

    // The auctioneer could claim the proceeds after the auction is successfully ended
    public fun claim<T0: store, T1> (auction: Auction<T0, T1>, auction_cap: AuctionCap): Balance<T1> {
        assert!(object::uid_to_inner(&auction.id) == auction_cap.auction_id, EAuctionIDMismatch);
        assert!(auction.has_ended, EAuctionHasNotEnded);
        let Auction { id, item, present_price: _, has_ended: _, proceed } = auction;
        object::delete(id);
        option::destroy_none(item);
        let AuctionCap { id, auction_id: _ } = auction_cap;
        object::delete(id);
        proceed
    }

    // The auctioneer could stop the auction before the auction is ended
    public fun stop<T0: store, T1> (auction: Auction<T0, T1>, auction_cap: AuctionCap): T0 {
        assert!(object::uid_to_inner(&auction.id) == auction_cap.auction_id, EAuctionIDMismatch);
        assert!(!auction.has_ended, EAuctionHasEnded);
        let Auction { id, item, present_price: _, has_ended: _, proceed } = auction;
        event::emit(AuctionStopped {
            auction_id: object::uid_to_inner(&id)
        });
        object::delete(id);
        balance::destroy_zero(proceed);
        let item = option::destroy_some(item);
        let AuctionCap { id, auction_id: _ } = auction_cap;
        object::delete(id);
        item
    }

    //==============================================================================================
    // Additional functions
    //==============================================================================================

    // Get auction proceeds balance
    public fun get_proceeds<T0: store, T1> (auction: &Auction<T0, T1>): u64 {
        auction.proceed.value()
    }

    // Check if a specific address is the auctioneer
    public fun is_auctioneer<T0: store, T1>(auction: &Auction<T0, T1>, auction_cap: &AuctionCap, addr: address): bool {
        object::uid_to_inner(&auction.id) == auction_cap.auction_id && tx_context::sender(ctx) == addr
    }
}
