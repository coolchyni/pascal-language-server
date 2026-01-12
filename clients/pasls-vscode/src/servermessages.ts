import * as vscode from "vscode";

export interface InputRegion {
	startLine: number;
	startCol:number;
	endLine: number;
	endCol:number;
}

export interface DecorationRangesPair {
	decoration: vscode.TextEditorDecorationType;
	ranges: vscode.Range[];
}

export interface InactiveRegionParams {
	uri: string;
	fileVersion: number;
	regions: InputRegion[];
}

