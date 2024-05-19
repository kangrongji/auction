# Reverse Auction

This Move smart contract module, auction::auction, implements a basic auction system on the Sui blockchain. It includes functionalities for creating auctions, setting new prices, bidding, and claiming auction proceeds. Here's a summary of the key features:

Auction Creation: Allows an auctioneer to create a new auction with an item and a maximum price. The auction details are encapsulated in an Auction struct, and an AuctionCap is issued to the auctioneer.

Setting Price: The auctioneer can set a new, lower price during the auction using the set_price function.

Bidding: Participants can bid on the auction. If the bid meets or exceeds the current price, the auction ends, and the item is transferred to the bidder. The bid amount is recorded as the auction's proceeds.

Claiming Proceeds: After the auction ends, the auctioneer can claim the proceeds using the claim function.

Stopping Auction: The auctioneer can stop the auction prematurely, reclaiming the item and terminating the auction.

Additional Functions: The module includes getter functions to check the auction's current price, status, and proceeds, and to verify the auctioneer's identity.

The contract emits events to notify users about important actions like auction creation, price setting, successful bidding, and auction stopping, enhancing transparency and traceability.