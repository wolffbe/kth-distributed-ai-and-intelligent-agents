/**
* Name: main
* Entry point for festival simulation 
* Author: Conor, Edwin, Benedict
* Tags: 
*/


model festival

global {
	int guestNumber <- 20;
	int foodStoreNumber <- 2;
	int waterStoreNumber <- 2;
	InformationCenter infoCenter;
	int auctions <- 3;
	int completedAuctions <- 0;
	
	int auctionParticipationRadius <- 5;
		
	init {
		// `with` allows passing a map of key-value pairs to initialize attributes- enable cache for approximately half the guests
		create Guest number: guestNumber with: [
			useCache::flip(0.5)
		];
		create InformationCenter {
			infoCenter <- self;
		}
		create Store number: foodStoreNumber {
			hasFood <- true;
		}
		create Store number: waterStoreNumber {
			hasWater <- true;
		}
		create Guard;
		create Auctioneer number: auctions;
	}
	
	reflex printAverageSteps when: cycle mod 500 = 0 {
		float averageStepsCache <- sum(Guest where each.useCache collect each.steps) / length(Guest where each.useCache);
		float averageStepsNoCache <- sum(Guest where !each.useCache collect each.steps) / length(Guest where !each.useCache);
		write "Average steps by: \n- brain: " + round(averageStepsCache) + 
			"\n- no brain " + round(averageStepsNoCache) + "\nat cycle: " + cycle + "\n";		
	}
	
	reflex printGlobalMerchandise when: cycle mod 1000 = 0 {
		write "Global remaining merchandise to auction: " + sum(Auctioneer collect each.items);
	}
	
	reflex printGlobalPurse {
		int globalMerchandise <- sum(Auctioneer collect each.items);
		if globalMerchandise = 0 {
			write "Global purse of all auctioneers" + sum(Auctioneer collect each.purse);
		}
	}
		
	action sometimes_log(float prob, string text) {
		if (rnd(1.0) < prob) {
			write text;
		}
	}
}

species Guest skills: [moving, fipa] {
	// randomize hunger/thirst levels to start in range [10, 100] for each guest, and decrease at
	// varying rates
	float food <- rnd(50.0, 100.0) update: food - rnd(0.1, 1.0);
	float water <- rnd(50.0, 100.0) update: water - rnd(0.1, 2.0);
	Store targetStore <- nil;
	
	bool useCache <- false;
	Store cachedFood <- nil;
	Store cachedWater <- nil;
	int steps <- 0;
	
	bool isBad <- flip(0.2);
	list<Guest> guestsToReport <- [];
	
	Auctioneer targetAuction <- nil;
	string soughtItem <- one_of(["hoodie", "t-shirt", "socks"]);
	int purchasePrice <- rnd(10, 100);
	int purse <- 1100;
	int items <- 0;
	
	bool isHungry {
		return food < 20;
	}
	
	bool isThirsty {
		return water < 20;
	}
	
	bool inAuction {
		return targetAuction != nil;
	}
	
	bool inDutchAuction {
		return targetAuction != nil and targetAuction.auctionType = "dutch";
	}
	
	bool inSealedBidAuction {
		return targetAuction != nil and targetAuction.auctionType = "sealed-bid";
	}
	
	bool inVickreyAuction {
		return targetAuction != nil and targetAuction.auctionType = "vickrey";
	}

	// small chance to forget
	reflex forget when: flip(0.01) {
	    string forgets <- one_of(["food", "water"]);
	    if (forgets = "food") {
	    	if (cachedFood != nil) {
	    		ask world {
	    			do sometimes_log(0.1, myself.name + " decided to forget a food store.\n");
	    		}
	    	}
	    	cachedFood <- nil;
	    } else {
	    	if (cachedWater != nil) {
	    		ask world {
    				do sometimes_log(0.1, myself.name + " decided to forget a drink store.\n");
				}
			}
	    	cachedWater <- nil;
	    }
	}
	
	reflex move {
		// highest priority is going to auction
		if (targetAuction != nil) {
			// just keeps them in the vicinity of auction (don't want to all be on top of each other)
			if (distance_to(self, targetAuction) > auctionParticipationRadius) {
				do goto target: targetAuction;
			} else {
				do wander;
			}
		}
		// middle priority is reporting bad guests
		else if (!empty(guestsToReport)) {
			do goto target: infoCenter;
		} 
		// lowest priority is eating/drinking
		else if (isHungry() or isThirsty()) {
			do applyCache;
			if (targetStore = nil) {
				// guest is hungry/thirsty and hasn't gotten location of target store yet from InformationCenter or cache
				if (distance_to(self, infoCenter) < 1.0) {
					// guest is within range to ask InformationCenter for nearest store
					targetStore <- askForTargetStore();
					
					// occasionally log for observability
					ask world {
						do sometimes_log(0.1, myself.name + " couldn't remember a nearby store, but got it from\nthe information center.\n");
					}
					
					steps <- steps+1;
					do goto target: targetStore;
				}
				// guest isn't within range to ask, keep moving towards InformationCenter
				else {
					steps <- steps+1;
					do goto target: infoCenter;
				}
			} else {
				steps <- steps+1;
				do goto target: targetStore;
			}
		} else {
			// don't increment steps so we only track "productive steps"
			do wander;
		}
	}
	
	reflex eat when: targetStore != nil and distance_to(self, targetStore) < 1.0 and targetStore.hasFood {
    	food <- 100.0;
		do cacheStore(targetStore);
    	targetStore <- nil;
	}
	
	reflex drink when: targetStore != nil and distance_to(self, targetStore) < 1.0 and targetStore.hasWater {
    	water <- 100.0;
		do cacheStore(targetStore);
    	targetStore <- nil;
	}
	
	action cacheStore(Store store) {
		if (store.hasFood) {
			cachedFood <- store;
		}
		if (store.hasWater) {
			cachedWater <- store;
		}
	}
	
	action applyCache {
		if (targetStore != nil or useCache = false) {
			return;
		}
		if (isHungry() and cachedFood != nil) {
			targetStore <- cachedFood;
			// occasionally log cache use for observability
			ask world {
				do sometimes_log(0.1, myself.name + " has remembered a nearby food store.\n");
			}
		}
		else if (isThirsty() and cachedWater != nil) {
			targetStore <- cachedWater;
			// occasionally log cache use for observability
			ask world {
				do sometimes_log(0.1, myself.name + " has remembered a nearby drink store.\n");
			}
		}
	}

	reflex witness when: !isBad {
		// when a good guest gets close to a bad guest, report them
		list<Guest> badGuests <- Guest where (each.isBad and distance_to(each, self) < 3.0 and !(guestsToReport contains each));
		
		// occasionally log for observability
		ask world {
			if (!empty(badGuests)) {
			    do sometimes_log(0.05, myself.name + " has witnessed the following bad guests: " + collect(badGuests, each.name) + "\n");
			}
		}

		guestsToReport <- guestsToReport + badGuests;	
	}
	
	reflex report when: distance_to(self, infoCenter) < 1.0 and !empty(guestsToReport) {
		ask InformationCenter {
			do handleGuestsReport(myself.guestsToReport);
		}
		guestsToReport <- [];
	}

	// listen for announcements of auction start- engage if interested in the item (only if they're not a bad guest)
	reflex listenForAuctionStart when: !inAuction() and !empty(cfps) and !isBad and purse >= 100 {
		message auctionStart <- cfps[0];
		if (list(auctionStart.contents)[0] = 'invite') {
			if (list(auctionStart.contents)[1] = soughtItem) {
				do accept_proposal with: (message: auctionStart, contents: ["join"]);
				targetAuction <- auctionStart.sender;
			} else {
				ask world {
					do sometimes_log(0.1, "[" + myself.name + "]: could not care less about " + list(auctionStart.contents)[1] + " being auctioned.");
				}
			}
		}
	}
	
	// for each step of the Dutch auction, accept if your target price has been reached
	reflex handleDutchAuctionProposal when: inDutchAuction() and !empty(proposes) {
		message auctionProposal <- proposes[0];
		int price <- int(list(auctionProposal.contents)[1]);
		if (price <= purchasePrice) {
			do accept_proposal with: (message: auctionProposal, contents: ["accept", price]);
		}
	}
	
	reflex handleSealedBidAuctionProposal when: (inSealedBidAuction() or inVickreyAuction()) and !empty(proposes) {
		message auction <- proposes[0];
		if (list(auction.contents)[0] = 'bidRequest') {
			do accept_proposal with: (message: auction, contents: [purchasePrice]);
			write "[" + name + "]: (thinking) I'm going to bid " + purchasePrice + ".\n"; 
		}
	}
	
	// listen for the outcome of the auction (Guest is the winner, or auction ended)
	reflex listenForAuctionEnd when: inAuction() and !empty(informs) {
		message auctionEnd <- informs[0];
		if (list(auctionEnd.contents)[0] = 'winner') {
			write "[" + name + "]: I just found out I'm the auction winner!\n";
		}
		
		completedAuctions <- completedAuctions + 1;
		items <- items + 1;
		purse <- purse - purchasePrice;
		targetAuction <- nil;
	}

	Store askForTargetStore {
		Store store <- nil;
		ask InformationCenter {
			if (myself.isHungry() and myself.isThirsty()) {
				store <- self.getNearestStore(myself);
			} else if (myself.isHungry()) {
				store <- self.getNearestFoodStore(myself);
			} else {
				store <- self.getNearestWaterStore(myself);
			}
		}
		return store;
	}
	
	aspect base {
		rgb guestColor <- #green;
		if (inAuction()) {
			guestColor <- #greenyellow;
		} else if (isHungry() and isThirsty()) {
			guestColor <- #red;
		} else if (isHungry()) {
			guestColor <- #orange;
		} else if (isThirsty()) {
			guestColor <- #yellow;
		}
		
		if (self.isBad) {
			draw square(2) color: guestColor;
		} else {
			draw circle(1) color: guestColor;
		}
		
	}
}

species Guard skills: [moving] {
	bool isCalled <- false;
	list<Guest> targets <- [];
	
	reflex move {
		// prioritise handling existing bad guests over getting new reports
		if (!empty(targets)) {
			Guest target <- targets[0];
			do goto target: target;
			if (distance_to(self, target) < 1.0) {
				do arrest(target);
			}
		} else if (isCalled) {
			do goto(target: infoCenter);
		} else {
			do wander;
		}
	}
	
	reflex getReports when: distance_to(self, infoCenter) < 1.0 {
		ask InformationCenter {
			myself.targets <- union(myself.targets, self.reportedGuests);
		}
		isCalled <- false;
	}
	
	action arrest(Guest target) {
		write target.name + " has been arrested by the guard.\n" ;
		ask target {
			do die;
		}
		
		// remove target from targets
		targets >> target;
		
		ask infoCenter {
			do handleGuestArrest(target);
		}
	}
			
	aspect base {
		draw circle(2) color: #black;
	}
}

species InformationCenter {
	list<Guest> reportedGuests <- [];
				
	action getNearestStore(agent guest) {
        Store nearest <- closest_to(Store, guest);
        return nearest;
    }
	
	Store getNearestFoodStore(Guest guest) {
		list<Store> foodStores <- Store where (each.hasFood);
		return closest_to(foodStores, guest);
	}
	
	Store getNearestWaterStore(Guest guest) {
		list<Store> waterStores <- Store where (each.hasWater);
		return closest_to(waterStores, guest);
	}
		
	action handleGuestsReport(list<Guest> badGuests) {
		// while guest was travelling to infoCentre to report, bad guest could have been arrested
		badGuests <- badGuests where (!dead(each));
		
		list<Guest> newBadGuests <- badGuests - reportedGuests;
		if (!empty(newBadGuests)) {
			write "The following bad guests have been reported: " + collect(newBadGuests, each.name) + "\n";
		}
		
		// only log for observability for new reports
	    if (!empty(badGuests - reportedGuests)) {
	    	write "Guard has been called to the information center.\n";
	    }
		
		// avoid duplicates when multiple guests report same bad guests
	    reportedGuests <- reportedGuests union badGuests;
	    ask Guard {
	        self.isCalled <- true;
	    }
	}
	
	// remove arrested guest from reportedGuests
	action handleGuestArrest(Guest guest) {
		reportedGuests >> guest;
	}

	aspect base {
		draw hexagon(3) color: #salmon;
		draw "InfoCenter" color: #black at: location + {-3, 3};
	}
	
}

species Store {
	bool hasFood <- false;
	bool hasWater <- false;
	
	aspect base {
        draw triangle(2) color: (self.hasFood ? #darkgoldenrod : #darkblue);
        draw self.hasFood ? "food" : "water" color: #black at: location + {-1, 2};
    }
}

species Auctioneer skills: [moving, fipa] {
    string auctionedItem <- one_of(["hoodie", "t-shirt", "socks"]);
    int items <- 100;
    int purse <- 0;
    string auctionType <- one_of(["dutch", "sealed-bid", "vickrey"]);
    int startingPrice <- 200;
    int currentPrice <- startingPrice;
    int minimumPrice <- 100;
    bool selling <- false;
    bool auctionActive <- false;
    list<Guest> participants <- [];
    int auctionStartTime <- -2;
    bool bidRequestSent <- false;
    
    // move around while not in an auction
    reflex move {
    	if (!auctionActive) {
    		do wander;
    	}
    }

	// invite guests to participate in auction
    reflex beginAuction when: !auctionActive and flip(0.005) and items > 0 {
    	auctionStartTime <- int(time);
        do start_conversation to: list(Guest) protocol: 'fipa-propose' performative: 'cfp' 
           contents: ['invite', auctionedItem, auctionType];
        write "Inviting guests to participate in a " + auctionType + " auction for " + auctionedItem + "\n";
    }

	// if guests accept proposal to join auction, add them to participants
    reflex handleParticipationReplies when: !auctionActive and time = auctionStartTime + 1 {
    	loop reply over: accept_proposals {
    		string dummy <- reply.contents;	// read contents to remove from `accept_proposals`
            participants <- participants + reply.sender;
        }
        if ((auctionType = "dutch" and !empty(participants)) or ((auctionType = "sealed-bid" or auctionType = "vickrey") and length(participants) >= 2)) {
        	write "[" + name +  "] " + "Auction started: Selling " + auctionedItem + " with " + length(participants) + " participants.\n";
        } else {
        	write "[" + name +  "] " + "No interested participants, cancelling auction.\n";
        	auctionStartTime <- -1;
        }
    }
    
	reflex waitForGuestsToGather when: !empty(participants) and (participants max_of (location distance_to(each.location)) <= auctionParticipationRadius) 
		and !auctionActive {
	    auctionActive <- true;
        write "Auction started: Selling " + auctionedItem + " with " + length(participants) + " participants.\n";
	}

	// send a new decreased proposal every 5 cycles
    reflex sendDutchProposal when: auctionActive and auctionType = "dutch" and int(time) mod 5 = 0 {
    	if (currentPrice < minimumPrice) {
    		do start_conversation to: participants protocol: 'fipa_propose' performative: 'inform' contents: ['stop'];
    		write "[" + name +  "] " + "Auction has ended: minimum price exceeded.\n";
    		do resetAuction;
			return;
    	}
    	
    	write "Auction continues: current offer = " + currentPrice + ".\n"; 
        do start_conversation to: participants protocol: 'fipa_propose' performative: 'propose' contents: ['offer', currentPrice];
        
        currentPrice <- currentPrice - rnd(5, 15);
    }
    
    reflex requestSealedBids when: auctionActive and (auctionType = "sealed-bid" or auctionType = "vickrey") and int(time) mod 5 = 0 {
    	do start_conversation to: participants protocol: 'fipa_propose' performative: 'propose' contents: ['bidRequest'];
    	write "[" + name +  "] " + "Requesting bids!\n";
    	bidRequestSent <- true;
    }
    
    // once a guest has accepted a given proposal, end the auction
    reflex handleAcceptProposal when: auctionActive and auctionType = "dutch" and !(empty(accept_proposals)) {
    	message acceptance <- accept_proposals[0];
    	int price <- int(list(acceptance.contents)[1]);
    	write "[" + name +  "] " + "Auction has ended: " + Guest(acceptance.sender).name + " bought " + auctionedItem + " for " + price + ".\n";
    	
    	do start_conversation to: acceptance.sender protocol: 'fipa-propose' performative: 'inform' contents: ['winner'];
    	do start_conversation to: participants - acceptance.sender protocol: 'fipa_propose' performative: 'inform' contents: ['stop'];
    	
    	items <- items - 1;
    	purse <- purse + price;
    	
    	do resetAuction;
    }
    
    reflex handleSealedBids when: auctionActive and !(empty(accept_proposals)) and auctionType = "sealed-bid" {
    	list<message> bidResponders <- sort_by(accept_proposals, int(list(each.contents)[0]));
    	message winner <- bidResponders[length(bidResponders) - 1];
    	int price <- int(list(winner.contents)[0]);
    	write "[" + name +  "] " + "Auction has ended: " + Guest(winner.sender).name + " bought " + auctionedItem + " for " + price + " at " + auctionType + " auction.\n";
    	
    	do start_conversation to: winner.sender protocol: 'fipa-propose' performative: 'inform' contents: ['winner'];
    	do start_conversation to: participants - winner.sender protocol: 'fipa_propose' performative: 'inform' contents: ['stop'];
    	
    	items <- items - 1;
    	purse <- purse + price;

    	do resetAuction;
    }
    
    reflex handleVickrey when: auctionActive and !(empty(accept_proposals)) and auctionType = "vickrey" {
    	list<message> bidResponders <- sort_by(accept_proposals, int(list(each.contents)[0]));
    	message winner <- bidResponders[length(bidResponders) - 1];
    	message secondHighestBidder <- bidResponders[length(bidResponders) - 2];
    	int winningPrice <- int(list(winner.contents)[0]);  	
    	int payingPrice <- int(list(secondHighestBidder.contents)[0]);
    	write "[" + name +  "] " + "Auction has ended: " + Guest(winner.sender).name + " bought " + auctionedItem + " for " + payingPrice + " after winning with the price of " + winningPrice + " at " + auctionType + " auction.\n";
    	
    	do start_conversation to: winner.sender protocol: 'fipa-propose' performative: 'inform' contents: ['winner'];
    	do start_conversation to: participants - winner.sender protocol: 'fipa_propose' performative: 'inform' contents: ['stop'];
    	
    	items <- items - 1;
    	purse <- purse + payingPrice;

    	do resetAuction;
    }
    
    action resetAuction {
    	auctionActive <- false;
    	selling <- false;
    	participants <- [];
    	currentPrice <- startingPrice;
    }
    
    aspect base {
    	draw square(3) color: #darkgrey;
    	draw "selling " + auctionedItem + " at " color: #black at: location + {-4, 3};
    	draw auctionType + " auction" color: #black at: location + {-4, 5};
    }
}

experiment festivalSimulation type:gui {
	output {
		display festivalDisplay {
			species Guest aspect:base;
			species Guard aspect:base;
			species InformationCenter aspect:base;
			species Store aspect:base;
			species Auctioneer aspect:base;
		}
	}
}

