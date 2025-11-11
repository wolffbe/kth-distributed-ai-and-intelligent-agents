/**
* Name: main
* Entry point for festival simulation 
* Author: conor, Edwin
* Tags: 
*/


model festival

global {
	int guestNumber <- 10;
	int foodStoreNumber <- 2;
	int waterStoreNumber <- 2;
	point infoCenterLocation;
	
	init {
		create Guest number: guestNumber;
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
	// randomize hunger/thirst levels to start in range [50, 100] for each guest, and decrease at
	// varying rates
	float hunger <- rnd(50.0, 100.0) update: hunger - rnd(0.5, 1);
	float thirst <- rnd(50.0, 100.0) update: thirst - rnd(0.5, 2);
	
	Store targetStore <- nil;
	
	// Challenge 1
	bool useCache <- false;
	int steps <- 0;
	Store cachedFood <- nil;
	Store cachedDrink <- nil;
	
	bool isHungry {
		return hunger < 20;
	}
	
	bool isThirsty {
		return thirst < 20;
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
		// guest is hungry/thirsty and hasn't gotten location of target store yet from InformationCenter or cache
		if ((isHungry() or isThirsty()) and targetStore = nil) {
			// guest is within range to ask InformationCenter for nearest store
			if (distance_to(self, infoCenterLocation) < 5.0) {
				targetStore <- askForTargetStore();
				steps <- steps+1;
				do goto target: targetStore;
			} 
			// guest isn't within range to ask, keep moving towards InformationCenter
			else {
				steps <- steps+1;
				do goto target: infoCenterLocation;
			}
		} 
		// guest has gotten location of nearest store and is on way to it
		else if (targetStore != nil) {
			steps <- steps+1;
			do goto target: targetStore;
			
		} else {
			// Steps intentionally not incremented as we only track "productive steps"
			do wander;
		}
	}
	
	reflex eat when: targetStore != nil and distance_to(self, targetStore) < 1.0 and targetStore.hasFood {
    	hunger <- 100.0;
		do cacheStore(targetStore);
    	targetStore <- nil;
	}
	
	reflex drink when: targetStore != nil and distance_to(self, targetStore) < 1.0 and targetStore.hasWater {
    	thirst <- 100.0;
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
		} else if (isThirsty()) {
			guestColor <- #orange;
		} else if (isHungry()) {
			guestColor <- #yellow;
		}
		
		draw circle(1) color: guestColor;
		
	}
}

species InformationCenter {
	
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
			species InformationCenter aspect:base;
			species Store aspect:base;
		}
	}
}

