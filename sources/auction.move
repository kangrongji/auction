module auction::auction {
    use sui::coin::{Self, Coin};
    use sui::balance::Balance;
    use sui::sui::SUI;

    use auction::library::{Self, Auction};

    // Error codes.

    /// A bid submitted for the wrong (e.g. non-existent) auction.
    const EWrongAuction: u64 = 1;

    /// Represents a bid sent by a bidder to the auctioneer.
    public struct Bid has key {
        id: UID,
        /// Address of the bidder
        bidder: address,
        /// ID of the Auction object this bid is intended for
        auction_id: ID,
        /// Coin used for bidding.
        bid: Balance<SUI>
    }

    // Entry functions.

    /// Creates an auction. It would be more natural to generate
    /// auction_id in create_auction and be able to return it so that
    /// it can be shared with bidders but we cannot do this at the
    /// moment. This is executed by the owner of the asset to be
    /// auctioned.
    public fun create_auction<T: key + store>(
        to_sell: T, auctioneer: address, ctx: &mut TxContext
    ): ID {
        let auction = library::create_auction(to_sell, ctx);
        let id = object::id(&auction);
        library::transfer(auction, auctioneer);
        id
    }

    /// Creates a bid a and send it to the auctioneer along with the
    /// ID of the auction. This is executed by a bidder.
    public fun bid(
        coin: Coin<SUI>, auction_id: ID, auctioneer: address, ctx: &mut TxContext
    ) {
        let bid = Bid {
            id: object::new(ctx),
            bidder: tx_context::sender(ctx),
            auction_id,
            bid: coin::into_balance(coin),
        };

        transfer::transfer(bid, auctioneer);
    }

    /// Updates the auction based on the information in the bid
    /// (update auction if higher bid received and send coin back for
    /// bids that are too low). This is executed by the auctioneer.
    public entry fun update_auction<T: key + store>(
        auction: &mut Auction<T>, bid: Bid, ctx: &mut TxContext
    ) {
        let Bid { id, bidder, auction_id, bid: balance } = bid;
        assert!(object::borrow_id(auction) == &auction_id, EWrongAuction);
        library::update_auction(auction, bidder, balance, ctx);

        object::delete(id);
    }

    /// Ends the auction - transfers item to the currently highest
    /// bidder or to the original owner if no bids have been
    /// placed. This is executed by the auctioneer.
    public entry fun end_auction<T: key + store>(
        auction: Auction<T>, ctx: &mut TxContext
    ) {
        library::end_and_destroy_auction(auction, ctx);
    }
}