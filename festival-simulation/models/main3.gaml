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
	int stageNumber <- 3;
	InformationCenter infoCenter;
	int auctions <- 3;
	
	int auctionParticipationRadius <- 5;
	float witnessDistance <- 3.0;
	int auctionCycleInterval <- 5;
	int stageRadius <- 3;
		
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
		create Stage number: stageNumber;
	}
	
	reflex printAverageSteps when: cycle mod 500 = 0 {
		// guard against division by zero
		list<Guest> cacheUsers <- Guest where each.useCache;
		list<Guest> nonCacheUsers <- Guest where !each.useCache;
		
		if (!empty(cacheUsers) and !empty(nonCacheUsers)) {
			float averageStepsCache <- sum(cacheUsers collect each.steps) / length(cacheUsers);
			float averageStepsNoCache <- sum(nonCacheUsers collect each.steps) / length(nonCacheUsers);
			write "Average steps by: \n- brain: " + round(averageStepsCache) + 
				"\n- no brain " + round(averageStepsNoCache) + "\nat cycle: " + cycle + "\n";
		}
	}
	
	reflex printAuctionStats when: cycle mod 1000 = 0 {
		int dutchCount <- sum(Auctioneer collect each.auctionCounts[0]);
		int sealedBidCount <- sum(Auctioneer collect each.auctionCounts[1]);
		int vickreyCount <- sum(Auctioneer collect each.auctionCounts[2]);
		
		// could handle granularly but this is easier
		if (dutchCount = 0 or sealedBidCount = 0 or vickreyCount = 0) {return;}
		
		float avgDutchRevenue <- sum(Auctioneer collect each.revenues[0]) / dutchCount;
		float avgSealedBidRevenue <- sum(Auctioneer collect each.revenues[1]) / sealedBidCount;
		float avgVickreyRevenue <- sum(Auctioneer collect each.revenues[2]) / vickreyCount;
		
		// guests didn't necessarily take part in all auctions of each type (if they were busy with another), but good enough estimate
		float avgDutchExpenditure <- sum(Guest collect each.expenditures[0]) / dutchCount;
		float avgSealedBidExpenditure <- sum(Guest collect each.expenditures[1]) / sealedBidCount;
		float avgVickreyExpenditure <- sum(Guest collect each.expenditures[2]) / vickreyCount;
		
		write "Auction statistics after " + cycle + " cycles (auction count, auctioneer revenue, guest expenditure):\n" +
			"Dutch: " + dutchCount + " auctions, " + round(avgDutchRevenue) + " avg revenue, " + round(avgDutchExpenditure) + " avg expenditure.\n" +
			"Sealed-bid: " + sealedBidCount + " auctions, " + round(avgSealedBidRevenue) + " avg revenue, " + round(avgSealedBidExpenditure) + " avg expenditure.\n" +
			"Vickrey: " + vickreyCount + " auctions, " + round(avgVickreyRevenue) + " avg revenue, " + round(avgVickreyExpenditure) + " avg expenditure.\n";
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
	int purchasePrice <- rnd(30, 120);
	list<int> expenditures <- [0, 0, 0]; // money spent in [dutch, sealed-bid, vickrey]
	
	// stage preferences
	float lightShowPref <- rnd(0.0, 1.0);
	float speakerPref <- rnd(0.0, 1.0);
	float musicStylePref <- rnd(0.0, 1.0);
	
	// stage-related state
	Stage targetStage <- nil;
	bool waitingForStageInfo <- false;
	map<Stage, list<float>> stageAttributes <- []; // stores received stage info
	int stageInfoRequestTime <- -1;
	
	
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
	
	bool atStage {
		return targetStage != nil and distance_to(self, targetStage) <= stageRadius;
	}
	
	bool goingToStage {
		return targetStage != nil;
	}
	
	// calculate utility for a stage based on guest preferences and stage attributes
	float calculateUtility(list<float> attrs) {
		// attrs: [lightShow, speaker, musicStyle]
		return lightShowPref * attrs[0] + speakerPref * attrs[1] + musicStylePref * attrs[2];
	}
	
	// select the best stage based on utility
	action selectBestStage {
		Stage bestStage <- nil;
		float bestUtility <- -1.0;
		
		loop stage over: stageAttributes.keys {
			float utility <- calculateUtility(stageAttributes[stage]);
			if (utility > bestUtility) {
				bestUtility <- utility;
				bestStage <- stage;
			}
		}
		
		if (bestStage != nil) {
			targetStage <- bestStage;
			write "[" + name + "]: Selected " + bestStage.name + " with utility " + bestUtility + "\n";
		}
		
		// clear the collected info for next time
		stageAttributes <- [];
		waitingForStageInfo <- false;
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
		// filter out already-arrested guests at the start to avoid control flow issues
		guestsToReport <- guestsToReport where (!dead(each));
		
		// highest priority is going to auction
		if (targetAuction != nil) {
			// leave stage if we were at one
			targetStage <- nil;
			// just keeps them in the vicinity of auction (don't want to all be on top of each other)
			if (distance_to(self, targetAuction) > auctionParticipationRadius) {
				do goto target: targetAuction;
			} else {
				do wander;
			}
		}
		// second priority is reporting bad guests
		else if (!empty(guestsToReport)) {
			do goto target: infoCenter;
		} 
		// third priority is eating/drinking
		else if (isHungry() or isThirsty()) {
			// leave stage if we were at one
			targetStage <- nil;
			
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
		}
		// fourth priority is going to/staying at a stage
		else if (goingToStage()) {
			if (atStage()) {
				do wander;
			} else {
				// traveling to stage
				do goto target: targetStage;
			}
		}
		// if nothing else to do and not waiting for stage info, query stages
		else if (!waitingForStageInfo and !isBad) {
			do queryStages;
		}
		else {
			// waiting for stage info or just wandering
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
		list<Guest> badGuests <- Guest where (each.isBad and distance_to(each, self) < witnessDistance and !(guestsToReport contains each));
		
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
	reflex listenForAuctionStart when: !inAuction() and !empty(cfps) and !isBad {
		loop auctionStart over: cfps {
			if (list(auctionStart.contents)[0] = 'invite') {
				if (list(auctionStart.contents)[1] = soughtItem) {
					do accept_proposal with: (message: auctionStart, contents: ["join"]);
					targetAuction <- auctionStart.sender;
					break;  // only join one auction
				} else {
					ask world {
						do sometimes_log(0.1, "[" + myself.name + "]: could not care less about " + list(auctionStart.contents)[1] + " being auctioned.\n");
					}
				}
			}
		}
	}
	
	// handle all auction proposals based on message content, not auctioneer state
	// only process proposals from the auctioneer we're currently participating with
	reflex handleAuctionProposal when: inAuction() and !empty(proposes) {
		loop auctionProposal over: proposes {
			// only process proposals from our current auctioneer
			if (auctionProposal.sender != targetAuction) {
				continue;
			}
			
			list contents <- list(auctionProposal.contents);
			
			// dutch auction: offer with price
			if (contents[0] = 'offer') {
				int price <- int(contents[1]);
				if (price <= purchasePrice) {
					do accept_proposal with: (message: auctionProposal, contents: ["accept", price]);
				}
			}
			// sealed-bid / vickrey auction: bid request
			else if (contents[0] = 'bidRequest') {
				do accept_proposal with: (message: auctionProposal, contents: [purchasePrice]);
				write "[" + name + "]: (thinking) I'm going to bid " + purchasePrice + ".\n"; 
			}
		}
	}
	
	// listen for the outcome of the auction
	reflex listenForAuctionEnd when: inAuction() and !empty(informs) {
		loop auctionEnd over: informs {
			// only process messages from our current auctioneer
			if (auctionEnd.sender != targetAuction) {
				continue;
			}
			
			if (list(auctionEnd.contents)[0] = 'winner') {
				// message format: ['winner', auctionType, pricePaid]
				string wonAuctionType <- string(list(auctionEnd.contents)[1]);
				int pricePaid <- int(list(auctionEnd.contents)[2]);
				
				write "[" + name + "]: I won the " + wonAuctionType + " auction and paid " + pricePaid + "!\n";
				
				if (wonAuctionType = "dutch") {
					expenditures[0] <- expenditures[0] + pricePaid;
				} else if (wonAuctionType = "sealed-bid") {
					expenditures[1] <- expenditures[1] + pricePaid;
				} else {
					expenditures[2] <- expenditures[2] + pricePaid;
				}
				
				targetAuction <- nil;
				purchasePrice <- rnd(30, 120); // randomize purchase price each round so not same guest always buying
			} else if (list(auctionEnd.contents)[0] = 'stop') {
				targetAuction <- nil;
				purchasePrice <- rnd(30, 120);
			}
		}
	}
	
	// query all stages for their attributes via FIPA
	action queryStages {
		waitingForStageInfo <- true;
		stageInfoRequestTime <- int(time);
		stageAttributes <- [];
		
		do start_conversation to: list(Stage) protocol: 'fipa-request' performative: 'request' 
			contents: ['getAttributes'];
		
		ask world {
			do sometimes_log(0.1, "[" + myself.name + "]: Querying stages for their attributes.\n");
		}
	}
	
	// handle stage info responses
	reflex handleStageInfo when: waitingForStageInfo and !empty(informs) {
		loop info over: informs {
			if (list(info.contents)[0] = 'stageInfo') {
				Stage sender <- info.sender;
				float lightShow <- float(list(info.contents)[1]);
				float speaker <- float(list(info.contents)[2]);
				float musicStyle <- float(list(info.contents)[3]);
				
				stageAttributes[sender] <- [lightShow, speaker, musicStyle];
			}
		}
		
		// once we have info from all stages, select the best one
		if (length(stageAttributes) = length(Stage)) {
			do selectBestStage;
		}
	}
	
	// timeout for stage info requests
	reflex stageInfoTimeout when: waitingForStageInfo and (int(time) - stageInfoRequestTime > 5) {
		// if we got at least one response, select from what we have
		if (!empty(stageAttributes)) {
			do selectBestStage;
		} else {
			// no responses, just stop waiting
			waitingForStageInfo <- false;
		}
	}
	
	// occasionally leave stage to find a new one (variety seeking)
	reflex leaveStage when: atStage() and flip(0.005) {
		write "[" + name + "]: Getting bored at " + targetStage.name + ", looking for a new stage.\n";
		targetStage <- nil;
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
		// filter out any dead targets first
		targets <- targets where (!dead(each));
		
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
			// filter out dead guests when picking up reports
			list<Guest> aliveReported <- self.reportedGuests where (!dead(each));
			myself.targets <- union(myself.targets, aliveReported);
		}
		isCalled <- false;
	}
	
	action arrest(Guest target) {
		// safety check in case target died between distance check and arrest
		if (dead(target)) {
			targets >> target;
			return;
		}
		
		write target.name + " has been arrested by the guard.\n";
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

species Stage skills: [fipa] {
	float lightShow <- rnd(0.0, 1.0);
	float speaker <- rnd(0.0, 1.0);
	float musicStyle <- rnd(0.0, 1.0);
	
	int actDuration <- rnd(100, 300);  // cycles per act
	int actStartTime <- 0;
	string currentAct <- "";
	list<string> allActs <- ["ABBA", "Roxette", "Ace of Base", "Zara Larsson", "Avicii"];
	
	init {
	    do pickNewAct;
	}
	
	action pickNewAct {
	    list<string> takenActs <- (Stage - self) collect each.currentAct;
	    list<string> availableActs <- allActs - takenActs;
	    
	    if (!empty(availableActs)) {
	        currentAct <- one_of(availableActs);
	    } else {
	        currentAct <- one_of(allActs);
	    }
	}
	
	reflex changeAct when: int(time) - actStartTime > actDuration {
		actStartTime <- int(time);
		actDuration <- rnd(100, 300);
		do pickNewAct;
		
		lightShow <- rnd(0.0, 1.0);
		speaker <- rnd(0.0, 1.0);
		musicStyle <- rnd(0.0, 1.0);
		
		write "[" + name + "]: New act starting - " + currentAct + 
			" (Light: " + (round(lightShow * 100) / 100) + 
			", Sound: " + (round(speaker * 100) / 100) + 
			", Style: " + (round(musicStyle * 100) / 100) + ")\n";
	}
	
	// respond to attribute requests from guests
	reflex handleAttributeRequests when: !empty(requests) {
		loop req over: requests {
			if (list(req.contents)[0] = 'getAttributes') {
				do start_conversation to: req.sender protocol: 'fipa-request' performative: 'inform'
					contents: ['stageInfo', lightShow, speaker, musicStyle];
			}
		}
	}
	
	aspect base {
		draw square(4) color: #purple;
		draw currentAct color: #black at: location + {-2, -3};
		draw name color: #black at: location + {-2, 4};
	}
}

species Auctioneer skills: [moving, fipa] {
    string auctionedItem <- one_of(["hoodie", "t-shirt", "socks"]);
    string auctionType <- one_of(["dutch", "sealed-bid", "vickrey"]);
    int startingPrice <- 200;
    int currentPrice <- startingPrice;
    int minimumPrice <- 100;
    bool auctionActive <- false;
    list<Guest> participants <- [];
    int auctionStartTime <- -2;
    list<int> revenues <- [0, 0, 0];	// revenue in [dutch, sealed-bid, vickrey]
    list<int> auctionCounts <- [0, 0, 0];	// number of auctions of type [dutch, sealed-bid, vickrey]
    bool bidsRequested <- false;	// flag to prevent repeated bid requests
    int bidRequestTime <- -1;		// timestamp when bids were requested (for timeout)
    
    // move around while not in an auction and not waiting for participants to gather
    reflex move {
    	if (!auctionActive and empty(participants)) {
    		do wander;
    	}
    }

	// invite guests to participate in auction
    reflex beginAuction when: !auctionActive and flip(0.005) {
    	auctionStartTime <- int(time);
        do start_conversation to: list(Guest) protocol: 'fipa-propose' performative: 'cfp' 
           contents: ['invite', auctionedItem, auctionType];
        write "[" + name +  "] " + "Inviting guests to participate in a " + auctionType + " auction for " + auctionedItem + "\n";
    }

	// if guests accept proposal to join auction, add them to participants
    reflex handleParticipationReplies when: !auctionActive and time = auctionStartTime + 1 {
    	loop reply over: accept_proposals {
    		if (list(reply.contents)[0] = "join") {
    			participants <- participants + reply.sender;
    		}
        }
        if ((auctionType = "dutch" and !empty(participants)) or ((auctionType = "sealed-bid" or auctionType = "vickrey") and length(participants) >= 2)) {
        	write "[" + name +  "] " + "Selling " + auctionedItem + " with " + length(participants) + " participants in " + auctionType + " auction.\n";
        } else {
        	write "[" + name +  "] " + "No interested participants, cancelling auction.\n";
        	auctionStartTime <- -1;
        }
    }
    
	reflex waitForGuestsToGather when: !auctionActive and !empty(participants) {
		// remove any dead participants first
		participants <- participants where (!dead(each));
		
		// check if we still have enough participants
		bool hasEnoughParticipants <- (auctionType = "dutch" and !empty(participants)) or 
			((auctionType = "sealed-bid" or auctionType = "vickrey") and length(participants) >= 2);
		
		if (!hasEnoughParticipants) {
			write "[" + name + "] " + "Not enough participants remaining, cancelling auction.\n";
			do resetAuction;
			return;
		}
		
		bool allGathered <- (participants max_of (location distance_to(each.location))) <= auctionParticipationRadius;
		
		if (allGathered) {
			auctionActive <- true;
			write "[" + name + "] " + "Starting " + auctionType + " auction for " + auctionedItem + " with " + length(participants) + " participants.\n";
		}
	}
	
	// send a new decreased proposal every 5 cycles
    reflex sendDutchProposal when: auctionActive and auctionType = "dutch" and int(time) mod auctionCycleInterval = 0 {
    	participants <- participants where (!dead(each));
    	
    	if (empty(participants)) {
    		write "[" + name + "] " + "Dutch auction ended: all participants left.\n";
    		do resetAuction;
    		return;
    	}
    	
    	if (currentPrice < minimumPrice) {
    		do start_conversation to: participants protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];
    		write "[" + name +  "] " + "Dutch auction has ended: minimum price exceeded.\n";
    		do resetAuction;
			return;
    	}
    	
    	write "Auction continues: current offer = " + currentPrice + ".\n"; 
        do start_conversation to: participants protocol: 'fipa-propose' performative: 'propose' contents: ['offer', currentPrice];
        
        currentPrice <- currentPrice - rnd(5, 15);
    }
    
    reflex requestSealedBids when: auctionActive and (auctionType = "sealed-bid" or auctionType = "vickrey") and !bidsRequested {
    	participants <- participants where (!dead(each));
    	
    	if (length(participants) < 2) {
    		write "[" + name + "] " + auctionType + " auction ended: not enough participants remaining.\n";
    		do start_conversation to: participants protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];
    		do resetAuction;
    		return;
    	}
    	
    	do start_conversation to: participants protocol: 'fipa-propose' performative: 'propose' contents: ['bidRequest'];
    	write "[" + name +  "] " + "Requesting sealed bids!\n";
    	bidsRequested <- true;
    	bidRequestTime <- int(time);
    }
    
    // timeout for sealed-bid auctions if no bids received after 10 cycles
    reflex sealedBidTimeout when: auctionActive and bidsRequested and (auctionType = "sealed-bid" or auctionType = "vickrey") and (int(time) - bidRequestTime > 10) {
    	write "[" + name + "] " + auctionType + " auction timed out waiting for bids.\n";
    	do start_conversation to: participants protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];
    	do resetAuction;
    }
    
    // once a guest has accepted a given proposal, end the auction
    reflex handleAcceptProposal when: auctionActive and auctionType = "dutch" and !(empty(accept_proposals)) {
    	list<message> validAccepts <- [];
    	loop reply over: accept_proposals {
    		// Reject late joiners
    		if (list(reply.contents)[0] = "join") {
    			do start_conversation to: [reply.sender] protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];
    		}
    		// Process valid accepts
    		else if (list(reply.contents)[0] = "accept" and (participants contains reply.sender) and !dead(Guest(reply.sender))) {
    			validAccepts <- validAccepts + reply;
    		}
        }
        
        if (empty(validAccepts)) {
        	return;
        }
        
    	message acceptance <- validAccepts[0];
    	int price <- int(list(acceptance.contents)[1]);
    	write "[" + name +  "] " + "Auction has ended: " + Guest(acceptance.sender).name + " bought " + auctionedItem + " for " + price + ".\n";
    	
    	do addToRevenue(price);
    	
    	// send winner message with auction type and price paid
    	do start_conversation to: [acceptance.sender] protocol: 'fipa-propose' performative: 'inform' contents: ['winner', 'dutch', price];
    	do start_conversation to: participants - acceptance.sender protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];
    	
    	do resetAuction;
    }
    
    reflex handleSealedBids when: auctionActive and !(empty(accept_proposals)) and auctionType = "sealed-bid" {
    	list<message> validBids <- [];
    	loop reply over: accept_proposals {
    		if (length(list(reply.contents)) > 0 and list(reply.contents)[0] = "join") {
    			do start_conversation to: [reply.sender] protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];
    		}
    		else if (length(list(reply.contents)) = 1 and (participants contains reply.sender) and !dead(Guest(reply.sender))) {
    			validBids <- validBids + reply;
    		}
        }
        
        if (empty(validBids)) {
        	return;
        }
        
    	list<message> bidResponders <- sort_by(validBids, int(list(each.contents)[0]));
    	message winner <- bidResponders[length(bidResponders) - 1];
    	int price <- int(list(winner.contents)[0]);
    	write "[" + name +  "] " + "Auction has ended: " + Guest(winner.sender).name + " bought " + auctionedItem + " for " + price + " at " + auctionType + " auction.\n";
    	
    	do addToRevenue(price);
    	
    	// send winner message with auction type and price paid
    	do start_conversation to: [winner.sender] protocol: 'fipa-propose' performative: 'inform' contents: ['winner', 'sealed-bid', price];
    	do start_conversation to: participants - winner.sender protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];

    	do resetAuction;
    }
    
    reflex handleVickrey when: auctionActive and !(empty(accept_proposals)) and auctionType = "vickrey" {
    	list<message> validBids <- [];
    	loop reply over: accept_proposals {
    		if (length(list(reply.contents)) > 0 and list(reply.contents)[0] = "join") {
    			do start_conversation to: [reply.sender] protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];
    		}
    		else if (length(list(reply.contents)) = 1 and (participants contains reply.sender) and !dead(Guest(reply.sender))) {
    			validBids <- validBids + reply;
    		}
        }
        
        if (length(validBids) < 2) {
        	return;
        }
        
    	list<message> bidResponders <- sort_by(validBids, int(list(each.contents)[0]));
    	message winner <- bidResponders[length(bidResponders) - 1];
    	message secondHighestBidder <- bidResponders[length(bidResponders) - 2];
    	int winningPrice <- int(list(winner.contents)[0]);  	
    	int payingPrice <- int(list(secondHighestBidder.contents)[0]);
    	write "[" + name +  "] " + "Auction has ended: " + Guest(winner.sender).name + " bought " + auctionedItem + " for " + payingPrice + " after winning with the price of " + winningPrice + " at " + auctionType + " auction.\n";
    	
    	do addToRevenue(payingPrice);
    	
    	// send winner message with auction type and price paid
    	do start_conversation to: [winner.sender] protocol: 'fipa-propose' performative: 'inform' contents: ['winner', 'vickrey', payingPrice];
    	do start_conversation to: participants - winner.sender protocol: 'fipa-propose' performative: 'inform' contents: ['stop'];

    	do resetAuction;
    }
    
    action resetAuction {
    	auctionActive <- false;
    	participants <- [];
    	currentPrice <- startingPrice;
    	bidsRequested <- false;
    	bidRequestTime <- -1;
    	
    	// change item and auction type each time
    	auctionedItem <- one_of(["hoodie", "t-shirt", "socks"]);
    	auctionType <- one_of(["dutch", "sealed-bid", "vickrey"]);
    }
    
    action addToRevenue(int price) {
		if (auctionType = "dutch") {
			revenues[0] <- revenues[0] + price;
			auctionCounts[0] <- auctionCounts[0] + 1;
		} else if (auctionType = "sealed-bid") {
			revenues[1] <- revenues[1] + price;
			auctionCounts[1] <- auctionCounts[1] + 1;
		} else {
			revenues[2] <- revenues[2] + price;
			auctionCounts[2] <- auctionCounts[2] + 1;
		}
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
			species Stage aspect:base;
			species Auctioneer aspect:base;
		}
	}
}
