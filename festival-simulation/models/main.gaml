model festival

global {
	int guestNumber <- 50;
	int guardNumber <- 10;
	int foodStoreNumber <- 2;
	int waterStoreNumber <- 2;
	point infoCenterLocation;
	
	init {
		create Guest number: guestNumber;
		create Guard number: guardNumber;
		create InformationCenter {
			infoCenterLocation <- self.location;
		}
		create Store number: foodStoreNumber {
			hasFood <- true;
		}
		create Store number: waterStoreNumber {
			hasWater <- true;
		}
		
		// Enable cache for half the guests
		int halfGuests <- int(guestNumber / 2);
		loop i from: 0 to: halfGuests - 1 {
			ask Guest[i] {
				useCache <- true;
			}
		}
	}
	
	reflex printTotalSteps when: cycle mod 100000 = 0 {
		int totalStepsCache <- sum(Guest where each.useCache collect each.steps);
		int totalStepsNoCache <- sum(Guest where !each.useCache collect each.steps);
		write "Steps by brain: " + totalStepsCache + " steps by no brain " + totalStepsNoCache + " at cycle: " + cycle;
		ask Guest {
			steps <- 0;
		}		
	}
}

species Guest skills: [moving] {
	// randomize hunger/thirst levels to start in range [10, 100] for each guest, and increase at
	// varying rates
	float hunger <- rnd(10.0, 100.0) update: hunger + rnd(0.01, 0.1);
	float thirst <- rnd(10.0, 100.0) update: thirst + rnd(0.01, 0.1);
	bool isBad <- flip(0.3);
	list<Guest> badGuests <- nil;
	list<Guest> reportedGuests <- nil;
	
	Store targetStore <- nil;
	
	// Challenge 1
	bool useCache <- false;
	int steps <- 0;
	Store cachedFood <- nil;
	Store cachedDrink <- nil;
	
	bool isHungry {
		if (hunger > 80) {
			return true;
		} else {
			return false;
		}
	}
	
	bool isThirsty {
		if (thirst > 80) {
			return true;
		} else {
			return false;
		}
	}
	
	action maybeForget(string what) {
		if !flip(0.5) { // chance to forget
			return;
		}
		if (what = "food") {
			cachedFood <- nil;
			
		} else if (what = "drink") {
			cachedDrink <- nil;
		} else { // both
			cachedFood <- nil;
			cachedDrink <- nil;
		}
	}
	
	action maybeApplyCache {
		if (targetStore != nil or useCache = false) {
			return;
		}
		if (isHungry() and cachedFood != nil) {
			do maybeForget("food");
			targetStore <- cachedFood;
		}
		else if (isThirsty() and cachedDrink != nil) {
			do maybeForget("drink");
			targetStore <- cachedDrink;
		}
	}
	
	reflex move {
		do maybeApplyCache;
		if (!isBad and length(badGuests) > 0) {
			do goto target: infoCenterLocation;
		} else if (isHungry() or isThirsty()) {
			if (targetStore = nil) {
				// guest is hungry/thirsty and hasn't gotten location of target store yet from InformationCenter or cache
				if (distance_to(self, infoCenterLocation) < 1.0) {
					// guest is within range to ask InformationCenter for nearest store
					targetStore <- askForTargetStore();
					steps <- steps+1;
					do goto target: targetStore;
				}
				// guest isn't within range to ask, keep moving towards InformationCenter
				else {
					steps <- steps+1;
					do goto target: infoCenterLocation;
				}
			} else {
				steps <- steps+1;
				do goto target: targetStore;
			}
		} else {
			// Steps intentionally not incremented as we only track "productive steps"
			do wander;
		}
	}
	
	reflex eat when: targetStore != nil and distance_to(self, targetStore) < 1.0 and targetStore.hasFood {
    	hunger <- 0.0;
		do cacheStore(targetStore);
    	targetStore <- nil;
	}
	
	reflex drink when: targetStore != nil and distance_to(self, targetStore) < 1.0 and targetStore.hasWater {
    	thirst <- 0.0;
		do cacheStore(targetStore);
    	targetStore <- nil;
	}
	
	action cacheStore(Store store) {
		if (store.hasFood) {
			cachedFood <- store;
		}
		if (store.hasWater) {
			cachedDrink <- store;
		}
	}

	reflex witness {
		list<Guest> guests <- Guest where (each.isBad and distance_to(each, self) < 3.0);
		if !(reportedGuests contains_any guests) {
			badGuests <- badGuests + guests;
		}
	}
	
	reflex report when: distance_to(self, infoCenterLocation) < 1.0 {
		ask InformationCenter {
			do reportGuests(myself.badGuests);
		}
		reportedGuests <- reportedGuests + badGuests;
		badGuests <- nil;
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
		if (isThirsty()) {
			guestColor <- #orange;
		} else if (isHungry()) {
			guestColor <- #orange;
		} else if (self.isBad) {
			guestColor <- #red;
		}
		
		draw circle(1) color: guestColor;
	}
}

species Guard skills: [moving] {
	bool isCalled <- false;
	bool isIdle <- true;
	list<Guest> targets <- nil;
	
	reflex move {
		if (isCalled and !isIdle) {
			isIdle <- false;
			do goto(target: infoCenterLocation);
		} else {
			do wander;
		}
	}
	
	reflex report when: distance_to(self, infoCenterLocation) < 1.0 {
		ask InformationCenter {
			myself.targets <- self.reportedGuests;
		}
	}

	reflex arrest {
		list<Guest> guests <- Guest where (each.isBad and distance_to(each, self) < 1.0);
		if (targets contains_any guests) {
			ask Guest at_distance(1) {
				do die;
			}
			isIdle <- true;
		}
	}
			
	aspect base {
		rgb guardColor <- #blue;
		draw circle(1) color: guardColor;
	}
}

species InformationCenter {
	list<Guest> reportedGuests <- nil;
				
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
		
	InformationCenter getInformationCenter(Guard guard) {
		list<InformationCenter> informationCenters <- InformationCenter where (each != nil);
		return closest_to(informationCenters, guard);
	}
	
	action reportGuests(list<Guest> guests) {
		reportedGuests <- reportedGuests + guests;
		ask Guard {
			self.isCalled <- true;
		}
	}
	
	action getReport {
		ask Guard {
			self.isCalled <- false;
		}
		list<Guest> reports <- reportedGuests;
		self.reportedGuests <- nil;
		return reports;
	}

	aspect base {
		draw square(3) color: #salmon;
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
