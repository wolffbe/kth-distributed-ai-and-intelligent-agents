model nqueens

global {
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
	int row <- -1;
	int col <- -1;
	list<int> validColumns <- [];
	int colIndex <- 0;  // current index of valid
	
	int solutions <- 0; // only used by Q-0
	
	bool isValid(int _row, int _col) {
		loop pos over: previousPositions {
			int otherCol <- int(pos.x);
			int otherRow <- int(pos.y);
			
			if (otherRow = _row) {
				return false;
			}

			if (otherCol = _col) {
				return false;
			}
			
			// Diagonal
			if (abs(otherCol - _col) = abs(otherRow - _row)) {
				return false;
			}
		}
		return true;
	}

	// From some research it gets a lot "luckier" when you dont just go left to right - so lets not do that	
	list<int> getValidColumns(int _row) {
		// Generate column order: middle first, alternating outward
		list<int> colOrder <- [];
		int mid <- int(n / 2);
		colOrder <- colOrder + [mid];
		loop offset from: 1 to: mid {
			if (mid + offset < n) {
				colOrder <- colOrder + [mid + offset];
			}
			if (mid - offset >= 0) {
				colOrder <- colOrder + [mid - offset];
			}
		}

		// Filter to only valid columns
		list<int> result <- [];
		loop c over: colOrder {
			if (isValid(_row, c)) {
				result <- result + [c];
			}
		}
		return result;
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
				list<point> result <- list<point>(list(msg.contents)[1]) + [{col,row}];
				if (predecessor != nil) {
					do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['done', result];
				} else {
					// Entire stack
					write "Found solution: ";
					loop queen over: result {
						write "    " + queen;
					}
					solutions <- solutions + 1;
					// Keep looking :)
					// do tryNextPosition();
				}
				//write "Position: (" + col + ", " + row + ")";
			}
		}
	}
	
	action tryPlace {
		// goes to next possible column 
		if (colIndex < length(validColumns)) {
			col <- validColumns[colIndex];
			if (successor != nil) {
				do start_conversation to: [successor] protocol: 'fipa-propose' performative: 'inform' contents: ['place', row, previousPositions + [{col, row}]];
			} else {
				//write "Position: (" + col + ", " + row + ")";
				do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['done', [{col,row}]];
				// Keep looking!
				do tryNextPosition();
			}
		// or gives up
		} else {
			// No valid position found, backtrack
			if (predecessor != nil) {
				previousPositions <- [];
				col <- -1;
				validColumns <- [];
				colIndex <- 0;
				do start_conversation to: [predecessor] protocol: 'fipa-propose' performative: 'inform' contents: ['cant'];
			} else {
				write "No more solution exists! Found: " + solutions;
			}
		}
	}

	action findPlacement(int _row) {
		row <- _row;
		validColumns <- getValidColumns(_row);
		colIndex <- 0;
		do tryPlace();
	}

	action tryNextPosition {
		colIndex <- colIndex + 1;
		do tryPlace();
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
