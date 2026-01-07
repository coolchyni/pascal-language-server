// Pascal Language Server
// Copyright 2026 Simon Hsu

// This file is part of Pascal Language Server.

// Pascal Language Server is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation, either version 3 of
// the License, or (at your option) any later version.

// Pascal Language Server is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with Pascal Language Server.  If not, see
// <https://www.gnu.org/licenses/>.

unit PasLS.Rename;

{$mode objfpc}{$H+}

interface

uses
  { RTL }
  SysUtils, Classes,
  { Code Tools }
  CodeToolManager, CodeCache, CTUnitGraph, BasicCodeTools,
  { LazUtils }
  LazFileUtils, AVL_Tree,
  { Protocol }
  LSP.BaseTypes, LSP.Base, LSP.Basic, LSP.Rename;

type
  { TRenameRequest }

  { The rename request is sent from the client to the server to perform
    a workspace-wide rename of a symbol. }

  TRenameRequest = class(specialize TLSPRequest<TRenameParams, TWorkspaceEdit>)
  public
    function Process(var Params: TRenameParams): TWorkspaceEdit; override;
  end;

  { TPrepareRenameRequest }

  { The prepare rename request is sent from the client to the server to
    setup and test the validity of a rename operation at a given location. }

  TPrepareRenameRequest = class(specialize TLSPRequest<TPrepareRenameParams, TPrepareRenameResult>)
  public
    function Process(var Params: TPrepareRenameParams): TPrepareRenameResult; override;
  end;


implementation

uses
  PasLS.Settings, PasLS.Diagnostics, PasLS.CodeUtils;

{ TRenameRequest }

function TRenameRequest.Process(var Params: TRenameParams): TWorkspaceEdit;
var
  Path, Identifier, MainFilename: String;
  X, Y: Integer;
  DeclCode, StartSrcCode: TCodeBuffer;
  DeclX, DeclY, DeclTopLine: Integer;
  DeclCaretXY: TPoint;
  TreeOfPCodeXYPosition: TAVLTree;
  Files: TStringList;
  ANode, Node: TAVLTreeNode;
  CodePos: PCodeXYPosition;
  CurrentURI: String;
  TextDocumentEdit: TTextDocumentEdit;
  TextEdit: TTextEdit;
  Graph: TUsesGraph;
  Completed: Boolean;
  UGUnit: TUGUnit;
begin
  Result := nil;
  
  with Params do
  begin
    Path := textDocument.LocalPath;
    X := position.character + 1;  // Convert to 1-based
    Y := position.line + 1;       // Convert to 1-based

    // Step 1: Load the file
    StartSrcCode := CodeToolBoss.LoadFile(Path, false, false);
    if StartSrcCode = nil then
    begin
      DoLog('Unable to load file: %s', [Path]);
      exit;
    end;

    // Step 2: Find the main declaration
    if not CodeToolBoss.FindMainDeclaration(StartSrcCode, X, Y, 
      DeclCode, DeclX, DeclY, DeclTopLine) then
    begin
      PublishCodeToolsError(Transport, 'FindMainDeclaration failed in ' + StartSrcCode.FileName + ' at ' + IntToStr(Y) + ':' + IntToStr(X));
      exit;
    end;

    // Step 3: Get the identifier at the declaration
    CodeToolBoss.GetIdentifierAt(DeclCode, DeclX, DeclY, Identifier);
    if Identifier = '' then
    begin
      DoLog('No identifier found at position');
      exit;
    end;
    
    DoLog('Found identifier: %s', [Identifier]);

    // Step 4: Collect all modules of program
    Files := TStringList.Create;
    TreeOfPCodeXYPosition := nil;
    try
      Files.Add(DeclCode.Filename);
      if CompareFilenames(DeclCode.Filename, StartSrcCode.Filename) <> 0 then
        Files.Add(StartSrcCode.Filename);

      // Determine main filename
      if ServerSettings.&program <> '' then
        MainFilename := ServerSettings.&program
      else
        MainFilename := Path;

      // Collect project units and pre-load them before building the uses graph
      GetProjectUnits(MainFilename, Files, False, Transport);
      
      // Step 5: Find references in all files using FindReferencesInFiles
      DoLog('Searching references in %d files...', [Files.Count]);
      DeclCaretXY.X := DeclX;
      DeclCaretXY.Y := DeclY;
      if not CodeToolBoss.FindReferencesInFiles(Files, DeclCode, DeclCaretXY,
        False, TreeOfPCodeXYPosition) then
      begin
        PublishCodeToolsError(Transport, 'FindReferencesInFiles failed');
        exit;
      end;

      // Step 6: Check if any references found
      if (TreeOfPCodeXYPosition = nil) or (TreeOfPCodeXYPosition.Count = 0) then
      begin
        DoLog('No references found for identifier: %s', [Identifier]);
        exit;
      end;

      DoLog('Found %d reference(s)', [TreeOfPCodeXYPosition.Count]);

      // 6. Create workspace edit with all changes
      Result := TWorkspaceEdit.Create;
      CurrentURI := '';
      TextDocumentEdit := nil;

      // Process all references from lowest to highest
      ANode := TAVLTreeNode(TreeOfPCodeXYPosition.FindLowest);
      while ANode <> nil do
      begin
        CodePos := PCodeXYPosition(ANode.Data);
        
        // Convert file path to URI
        Path := PathToURI(CodePos^.Code.Filename);
        
        // Create new TextDocumentEdit for each different file
        if Path <> CurrentURI then
        begin
          CurrentURI := Path;
          TextDocumentEdit := Result.documentChanges.Add;
          TextDocumentEdit.textDocument.uri := CurrentURI;
          if ClientInfo.name = TClients.SublimeTextLSP then  
            TextDocumentEdit.textDocument.version := nil
          else
            TextDocumentEdit.textDocument.version := 0;
        end;

        // Create text edit for this reference
        TextEdit := TextDocumentEdit.edits.Add;
        TextEdit.range.start.line := CodePos^.Y - 1;        // Convert to 0-based
        TextEdit.range.start.character := CodePos^.X - 1;   // Convert to 0-based
        TextEdit.range.&end.line := CodePos^.Y - 1;
        TextEdit.range.&end.character := CodePos^.X - 1 + Length(Identifier);
        TextEdit.newText := newName;

        DoLog('Rename at: %s @ %d,%d', [CodePos^.Code.Filename, CodePos^.Y, CodePos^.X]);
        
        ANode := TAVLTreeNode(TreeOfPCodeXYPosition.FindSuccessor(ANode));
      end;

    finally
      CodeToolBoss.FreeTreeOfPCodeXYPosition(TreeOfPCodeXYPosition);
      Files.Free;
    end;
  end;
end;

{ TPrepareRenameRequest }

function TPrepareRenameRequest.Process(var Params: TPrepareRenameParams): TPrepareRenameResult;
var
  Code: TCodeBuffer;
  X, Y: Integer;
  DeclCode: TCodeBuffer;
  DeclX, DeclY, DeclTopLine: Integer;
  Identifier: string;
begin
  Result := nil;
  
  with Params do
  begin
    Code := CodeToolBoss.FindFile(textDocument.LocalPath);
    if Code = nil then
      Code := CodeToolBoss.LoadFile(textDocument.LocalPath, false, false);
      
    if Code = nil then
    begin
      DoLog('Cannot prepare rename: file not found');
      exit;
    end;
      
    X := position.character + 1;  // Convert to 1-based
    Y := position.line + 1;       // Convert to 1-based

    try
      // Find the main declaration to verify this is a valid identifier
      if not CodeToolBoss.FindMainDeclaration(Code, X, Y,
        DeclCode, DeclX, DeclY, DeclTopLine) then
      begin
        DoLog('Cannot prepare rename: no declaration found');
        exit;
      end;

      // Get the identifier name at the declaration
      CodeToolBoss.GetIdentifierAt(DeclCode, DeclX, DeclY, Identifier);
      
      if Identifier = '' then
      begin
        DoLog('Cannot prepare rename: no identifier at position');
        exit;
      end;

      // Create result with range and placeholder (0-based coordinates for LSP)
      Result := TPrepareRenameResult.Create;
      Result.range.start.line := position.line;
      Result.range.start.character := position.character;
      Result.range.&end.line := position.line;
      Result.range.&end.character := position.character + Length(Identifier);
      Result.placeholder := Identifier;

      DoLog('Prepare rename for: %s', [Identifier]);

    except
      on E: Exception do
      begin
        LogError('PrepareRename Error', E);
        FreeAndNil(Result);
      end;
    end;
  end;
end;

end.
