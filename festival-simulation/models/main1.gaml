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
	}
	
	reflex printAverageSteps when: cycle mod 500 = 0 {
		float averageStepsCache <- sum(Guest where each.useCache collect each.steps) / length(Guest where each.useCache);
		float averageStepsNoCache <- sum(Guest where !each.useCache collect each.steps) / length(Guest where !each.useCache);
		write "Average steps by: \n- brain: " + round(averageStepsCache) + 
			"\n- no brain " + round(averageStepsNoCache) + "\nat cycle: " + cycle + "\n";		
	}
	
	action sometimes_log(float prob, string text) {
		if (rnd(1.0) < prob) {
			write text;
		}
	}
}

species Guest skills: [moving] {
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
	
	bool isHungry {
		return food < 20;
	}
	
	bool isThirsty {
		return water < 20;
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
		// report bad guests with priority
		if (!empty(guestsToReport)) {
			do goto target: infoCenter;
		} else if (isHungry() or isThirsty()) {
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
		if (isHungry() and isThirsty()) {
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

experiment festivalSimulation type:gui {
	output {
		display festivalDisplay {
			species Guest aspect:base;
			species Guard aspect:base;
			species InformationCenter aspect:base;
			species Store aspect:base;
		}
	}
}
