model nqueens

global {
	// 17 works
	// 18 finishes
	// 19 finishes quickly
	// 20 does but in _
	int n <- 20;
	float cellSize <- 100 / n;  // Grid cell size for display

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
	
	reflex kickOff when: cycle = 10 {
		Queen firstQueen <- Queen[0];
		ask firstQueen {
			do findPlacement(0);
		}
	}
}

species Queen skills: [fipa] {
	Queen predecessor <- nil;
	Queen successor <- nil;
	list<point> previousPositions <- [];
	bool isSolved <- false;
	int row <- -1;
	int col <- -1;

	init {
		row <- -1;
		col <- -1;
	}
	
	bool isValid(int _row, int _col) {
		loop pos over: previousPositions {
			int otherCol <- int(pos.x);
			int otherRow <- int(pos.y);
			
			// Same row
			if (otherRow = _row) {
				return false;
			}
			
			// Same column
			if (otherCol = _col) {
				return false;
			}
			
			// Diagonal check
			if (abs(otherCol - _col) = abs(otherRow - _row)) {
				return false;
			}
		}
		return true;
	}
	
	bool successorPlacementExists(int _row, int _col) {
		bool any <- false;
		previousPositions <- previousPositions + [{_col, _row}];
		loop c from: 0 to: n - 1 {
			if (isValid(_row+1, c)) {
				any <- true;
				break;
			}
		}
		previousPositions <- previousPositions - [{_col, _row}];
		return any;
	}
	
	reflex handleMessages when: !empty(informs) {
		loop msg over: informs {
			string msgType <- string(list(msg.contents)[0]);
			
			if (msgType = "place") {
				int _row <- int(list(msg.contents)[1]);
				previousPositions <- list<point>(list(msg.contents)[2]);
				do findPlacement(_row + 1);
			}
			else if (msgType = "cant") {
				do tryNextPosition();
			}
			else if (msgType = "done") {
				write "[" + name + "] Solution found!";
				isSolved <- true;
				if (predecessor != nil) {
					do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['done'];
				} else {
					write "Found solution :)";
				}
				write "Position: (" + col + ", " + row + ")";
			}
		}
	}
	
	action findPlacement(int _row) {
		row <- _row;
		loop c from: 0 to: n - 1 {
			if (isValid(row, c) and (successor = nil or successorPlacementExists(row, c))) {
				col <- c;
				if (successor != nil) {
					do start_conversation to: [successor] protocol: 'fipa-propose' performative: 'inform' contents: ['place', row, previousPositions + [{col, row}]];
				} else {
					write "Position: (" + col + ", " + row + ")";
					do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['done'];
				}
				return;
			}
		}
		
		// No valid placement found
		if (predecessor != nil) {
			previousPositions <- [];
			do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['cant'];
		} else {
			write "No solution exists!";
		}
	}
	
	action tryNextPosition {
		loop c from: col + 1 to: n - 1 {
			if (col = n - 1) {
				break;
			}
			if (isValid(row, c) and (successor = nil or successorPlacementExists(row, c))) {
				col <- c;
				do start_conversation to: [successor] protocol: 'fipa-propose' performative: 'inform' contents: ['place', row, previousPositions + [{col, row}]];
				return;
			}
		}
		
		// No valid position found, backtrack
		if (predecessor != nil) {
			previousPositions <- [];
			col <- -1;  // Reset column
			do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['cant'];
		} else {
			write "No solution exists!";
		}
	}
	
	// Draw queen on grid based on row and col
	aspect base {
		if (col >= 0 and row >= 0) {
			// Calculate grid position
			float xPos <- (col + 0.5) * cellSize;
			float yPos <- (row + 0.5) * cellSize;
			draw circle(cellSize * 0.4) at: {xPos, yPos} color: #green;
		}
	}
}

experiment nqueensSimulation type: gui {
	output {
		display queensDisplay {
			// Draw the chess board grid
			graphics "grid" {
				loop i from: 0 to: n - 1 {
					loop j from: 0 to: n - 1 {
						rgb cellColor <- ((i + j) mod 2 = 0) ? #white : #lightgray;
						draw rectangle(cellSize, cellSize) at: {(i + 0.5) * cellSize, (j + 0.5) * cellSize} color: cellColor;
					}
				}
			}
			species Queen aspect: base;
		}
	}
}
