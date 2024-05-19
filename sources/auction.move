module auction::auction {

    use sui::balance::{Self, Balance};
    use sui::event::{Self};

    // Errors
    const EAuctionHasEnded: u64 = 0;
    const EAuctionHasNotEnded: u64 = 1;
    const EBalanceNotEnough: u64 = 2;
    const ENewPriceMustBeLower: u64 = 3;
    const EAuctionIDMismatch: u64 = 4;

    //Events
    public struct AuctionCreated has copy, drop {
        auction_id: ID,
        maximal_price: u64,
    }

    public struct NewPriceSetted has copy, drop {
        auction_id: ID,
        new_price: u64,
    }

    public struct AuctionEnded has copy, drop {
        auction_id: ID,
        final_price: u64,
        bidder_address: address,
    }

    public struct AuctionStopped has copy, drop {
        auction_id: ID,
    }

    // The auction object
    public struct Auction<T0: store, phantom T1> has key {
        id: UID,
        item: Option<T0>,
        present_price: u64,
        has_ended: bool,
        proceed: Balance<T1>
    }

    // Capability of being the auctioneer
    public struct AuctCap has key, store {
        id: UID,
        auction_id: ID
    }

    // Create a new auction
    public fun create<T0: store, T1> (item: T0, maximal_price: u64, ctx: &mut TxContext): AuctCap {
        let auction = Auction<T0, T1> {
            id: object::new(ctx),
            item: option::some(item),
            present_price: maximal_price,
            has_ended: false,
            proceed: balance::zero()
        };
        let auct_cap = AuctCap {
            id: object::new(ctx),
            auction_id: object::uid_to_inner(&auction.id)
        };
        event::emit(AuctionCreated {
            auction_id: object::uid_to_inner(&auction.id),
            maximal_price: auction.present_price
        });
        transfer::share_object(auction);
        return auct_cap
    }

    // The auctioneer could set a new auction price
    public fun set_price<T0: store, T1> (auction: &mut Auction<T0, T1>, auct_cap: &AuctCap, new_price: u64) {
        assert!(object::uid_to_inner(&auction.id) == auct_cap.auction_id, EAuctionIDMismatch);
        assert!(!auction.has_ended, EAuctionHasEnded);
        assert!(new_price < auction.present_price, ENewPriceMustBeLower);
        auction.present_price = new_price;
        event::emit(NewPriceSetted {
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
        event::emit(AuctionEnded {
            auction_id: object::uid_to_inner(&auction.id),
            final_price: auction.present_price,
            bidder_address: ctx.sender()
        });
        return (item, bid_balance)
    }

    // The auctioneer could claim the proceeds after the auction is successfully ended
    public fun claim<T0: store, T1> (auction: Auction<T0, T1>, auct_cap: AuctCap): Balance<T1> {
        assert!(object::uid_to_inner(&auction.id) == auct_cap.auction_id, EAuctionIDMismatch);
        assert!(auction.has_ended, EAuctionHasNotEnded);
        let Auction<T0, T1> { id, item, present_price: _, has_ended: _, proceed } = auction;
        object::delete(id);
        option::destroy_none(item);
        let AuctCap { id, auction_id: _ } = auct_cap;
        object::delete(id);
        return proceed
    }

    // The auctioneer could stop the auction before the auction is ended
    public fun stop<T0: store, T1> (auction: Auction<T0, T1>, auct_cap: AuctCap): T0 {
        assert!(object::uid_to_inner(&auction.id) == auct_cap.auction_id, EAuctionIDMismatch);
        assert!(!auction.has_ended, EAuctionHasEnded);
        let Auction<T0, T1> { id, item, present_price: _, has_ended: _, proceed } = auction;
        event::emit(AuctionStopped {
            auction_id: object::uid_to_inner(&id)
        });
        object::delete(id);
        balance::destroy_zero(proceed);
        let item = option::destroy_some(item);
        let AuctCap { id, auction_id: _ } = auct_cap;
        object::delete(id);
        return item
    }

    //Getter
    public fun get_present_price<T0: store, T1> (auction: &Auction<T0, T1>): u64 {
        return auction.present_price
    }


}
