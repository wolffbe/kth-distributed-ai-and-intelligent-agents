model nqueens


global {
	int n <- 8;

	init {
		create Queen number: n returns: queens;
		
		loop i from: 0 to: n - 1 {
			if (i > 0) {
				queens[i].predecessor <- queens[i - 1];
			}
			if (i < n - 1) {
				queens[i].successor <- queens[i + 1];
			}
		}
		

	}
	
    reflex kickOff when: cycle=10 {
        Queen firstQueen <- Queen[0];
        ask firstQueen {
            do findPlacement(0);
        }
    }
}

species Queen skills: [fipa] {
	Queen predecessor <- nil; // prev
	Queen successor <- nil; // next
	list<point> previousPositions <- [];
	bool isSolved <- false;
	int row <- -1;
	


	init {
		location <- {-1, -1};
	}
	
    reflex connect when: time = 1 and successor != nil {
        do start_conversation to: [successor] protocol: 'fipa-propose' performative: 'cfp' contents: ['hello'];
    }
    
   reflex connectBack when: time = 1 and predecessor != nil {
        do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'cfp' contents: ['hello backwards'];
    }
    
    reflex handleCfp when: !empty(cfps) {
        loop msg over: cfps {
            string msgType <- string(list(msg.contents)[0]);
            write "[" + name + "] Received: " + msgType;
            
            // Reply with proposal (acknowledge)
            do propose message: msg contents: ['hello', msgType];
        }
    }
	
	list<point> getTaken {
		if (empty(previousPositions) and predecessor != nil) {
			ask predecessor {
				myself.previousPositions <- previousPositions + [location];
			}
		}
		//write previousPositions;
		return previousPositions;
	}
	
	bool isValid(int _row, int column) {
		loop pos over: getTaken() {
			int otherCol <- int(pos.x);
			int otherRow <- int(pos.y);
			
			// Same row
			if (otherRow = row) {
				return false;
			}
			
			// Same column
			if (otherCol = column) {
				return false;
			}
			
			// Diagonal check
			if (abs(otherCol - column) = abs(otherRow - row)) {
				return false;
			}
		}
		return true;
	}
	
	
	reflex handleMessages when: !empty(informs) {
	    loop msg over: informs {
	        string msgType <- string(list(msg.contents)[0]);
	        
	        if (msgType = "place") {
	       		int _row <- int(list(msg.contents)[1]);
	            // Predecessor is telling us to start placing ourselves
	            do findPlacement(_row+1);
	        }
	        else if (msgType = "cant") {
	            // Successor couldn't find valid placement - try our next position
	            do tryNextPosition();
	        }
	        else if (msgType = "done") {
	            // Success! Last queen found a home
	            write "[" + name + "] Solution found!";
	            isSolved <- true;
	            // Optionally notify predecessor
	            if (predecessor != nil) {
	                do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['done'];
	            } else {
	            	write "found solution :)";
	            }
	        }
	    }
	}
	
	action findPlacement(int _row) {
		row <- _row;
	    loop col from: 0 to: n - 1 {
	        if (isValid(row, col)) {
	            location <- {col, row};
	            if (successor != nil) {
	            	//write "Hello?";
	                do start_conversation to: [successor] protocol: 'fipa-propose' performative: 'inform' contents: ['place', row];
	            } else {
	                // I'm the last queen - we're done!
	                do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['done'];
	            }
	            return;
	        }
	    }
	    
	    // no placement
	    if (predecessor != nil) {
	    	previousPositions <- [];
	        do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['cant'];
	    }
	}
	
	action tryNextPosition {
	    // Try next column from current position
	    loop col from: int(location.x) + 1 to: n - 1 {
	    	if (location.x = n-1) {
	    		break;
	    	}
	        if (isValid(row, col)) {
	            location <- {col, row};
	            do start_conversation to: [successor] protocol: 'fipa-propose' performative: 'inform' contents: ['place', row];
	            return;
	        }
	    }
	    
	    // no spot found!
	    if (predecessor != nil) {
	        // Backtrack further
	        previousPositions <- [];
	        do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['cant'];
	    }
	}
	
	
	
	aspect base {
		draw circle(1) color: #green;
	}
	
}

experiment nqueensSimulation type:gui {
	output {
		display queensDisplay {
			species Queen aspect:base;
		}
	}
}
